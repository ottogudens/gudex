"""Central cash ledger for all confirmed income, expenses and internal transfers."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlmodel import Session, select

from app.database import get_session
from app.models import CashAccount, CashClosure, CashMovement, Customer, Vehicle, WorkOrder
from app.schemas import (CashAccountCreate, CashClosureClose, CashClosureOpen,
                         CashExpenseCreate, CashTransferCreate)
from app.security import require_admin
from app.services.cash import ensure_default_accounts

router = APIRouter(tags=["caja central"])

_OUTGOING = {"expense", "transfer_out", "reversal"}


def _account(session: Session, account_id: int) -> CashAccount:
    account = session.get(CashAccount, account_id)
    if not account or not account.active:
        raise HTTPException(422, "Selecciona una caja o cuenta activa")
    return account


def _validate_links(session: Session, customer_id: int | None, vehicle_id: int | None,
                    work_order_id: int | None) -> None:
    if customer_id and not session.get(Customer, customer_id):
        raise HTTPException(404, "Cliente no encontrado")
    if vehicle_id and not session.get(Vehicle, vehicle_id):
        raise HTTPException(404, "Vehículo no encontrado")
    if work_order_id and not session.get(WorkOrder, work_order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")


def _serialize(row: CashMovement, session: Session) -> dict:
    account = session.get(CashAccount, row.account_id)
    return {**row.model_dump(), "account_name": account.name if account else "Cuenta eliminada"}


@router.get("/api/v1/cash/accounts", dependencies=[Depends(require_admin)])
def list_cash_accounts(session: Session = Depends(get_session)):
    ensure_default_accounts(session)
    session.commit()
    return session.exec(select(CashAccount).order_by(CashAccount.kind, CashAccount.name)).all()


@router.post("/api/v1/cash/accounts", status_code=201, dependencies=[Depends(require_admin)])
def create_cash_account(data: CashAccountCreate, session: Session = Depends(get_session)):
    name = data.name.strip()
    if session.exec(select(CashAccount).where(CashAccount.name == name)).first():
        raise HTTPException(409, "Ya existe una caja o cuenta con ese nombre")
    account = CashAccount(name=name, kind=data.kind.strip().lower())
    session.add(account); session.commit(); session.refresh(account)
    return account


@router.get("/api/v1/cash/movements", dependencies=[Depends(require_admin)])
def list_cash_movements(from_date: datetime | None = None, to_date: datetime | None = None,
                        account_id: int | None = None, direction: str | None = None,
                        limit: int = 100, offset: int = 0,
                        session: Session = Depends(get_session)):
    statement = select(CashMovement).order_by(CashMovement.occurred_at.desc()).offset(max(offset, 0)).limit(min(max(limit, 1), 200))
    if from_date:
        statement = statement.where(CashMovement.occurred_at >= from_date)
    if to_date:
        statement = statement.where(CashMovement.occurred_at < to_date)
    if account_id:
        statement = statement.where(CashMovement.account_id == account_id)
    if direction:
        statement = statement.where(CashMovement.direction == direction)
    return [_serialize(row, session) for row in session.exec(statement).all()]


@router.get("/api/v1/cash/summary", dependencies=[Depends(require_admin)])
def cash_summary(from_date: datetime | None = None, to_date: datetime | None = None,
                 session: Session = Depends(get_session)):
    ensure_default_accounts(session)
    session.commit()
    rows = session.exec(select(CashMovement)).all()
    if from_date:
        rows = [row for row in rows if row.occurred_at >= from_date]
    if to_date:
        rows = [row for row in rows if row.occurred_at < to_date]
    accounts = session.exec(select(CashAccount).order_by(CashAccount.name)).all()
    by_account = []
    total_income = total_expense = 0
    for account in accounts:
        entries = [row for row in rows if row.account_id == account.id and row.status == "recorded"]
        incoming = sum(row.amount_clp for row in entries if row.direction in {"income", "transfer_in"})
        outgoing = sum(row.amount_clp for row in entries if row.direction in _OUTGOING)
        total_income += sum(row.amount_clp for row in entries if row.direction == "income")
        total_expense += sum(row.amount_clp for row in entries if row.direction in {"expense", "reversal"})
        by_account.append({"account": account, "incoming_clp": incoming, "outgoing_clp": outgoing,
                           "balance_clp": incoming - outgoing})
    open_closures = session.exec(select(CashClosure).where(CashClosure.status == "open")).all()
    return {"income_clp": total_income, "expense_clp": total_expense,
            "net_clp": total_income - total_expense, "accounts": by_account,
            "open_closures": open_closures}


@router.post("/api/v1/cash/expenses", status_code=201, dependencies=[Depends(require_admin)])
def create_cash_expense(data: CashExpenseCreate, request: Request, session: Session = Depends(get_session)):
    _account(session, data.account_id)
    _validate_links(session, data.customer_id, data.vehicle_id, data.work_order_id)
    movement = CashMovement(account_id=data.account_id, direction="expense", amount_clp=data.amount_clp,
        source_type="manual_expense", category=data.category.strip(), note=data.note.strip(),
        reference=data.reference.strip() if data.reference else None,
        counterparty=data.counterparty.strip() if data.counterparty else None,
        customer_id=data.customer_id, vehicle_id=data.vehicle_id, work_order_id=data.work_order_id,
        created_by_email=request.state.user_email)
    session.add(movement); session.commit(); session.refresh(movement)
    return _serialize(movement, session)


@router.post("/api/v1/cash/transfers", status_code=201, dependencies=[Depends(require_admin)])
def create_cash_transfer(data: CashTransferCreate, request: Request, session: Session = Depends(get_session)):
    if data.from_account_id == data.to_account_id:
        raise HTTPException(422, "Selecciona dos cuentas distintas para la transferencia")
    _account(session, data.from_account_id); _account(session, data.to_account_id)
    reference = data.reference.strip() if data.reference else f"TRF-{datetime.now():%y%m%d%H%M%S}"
    note = data.note.strip() or "Transferencia interna"
    outgoing = CashMovement(account_id=data.from_account_id, direction="transfer_out", amount_clp=data.amount_clp,
        source_type="internal_transfer", category="transferencia", note=note, reference=reference,
        created_by_email=request.state.user_email)
    incoming = CashMovement(account_id=data.to_account_id, direction="transfer_in", amount_clp=data.amount_clp,
        source_type="internal_transfer", category="transferencia", note=note, reference=reference,
        created_by_email=request.state.user_email)
    session.add(outgoing); session.add(incoming); session.commit(); session.refresh(outgoing); session.refresh(incoming)
    return {"outgoing": _serialize(outgoing, session), "incoming": _serialize(incoming, session)}


@router.post("/api/v1/cash/closures/open", status_code=201, dependencies=[Depends(require_admin)])
def open_cash_closure(data: CashClosureOpen, request: Request, session: Session = Depends(get_session)):
    _account(session, data.account_id)
    if session.exec(select(CashClosure).where(CashClosure.account_id == data.account_id, CashClosure.status == "open")).first():
        raise HTTPException(409, "Esta caja ya tiene un turno abierto")
    closure = CashClosure(account_id=data.account_id, opening_amount_clp=data.opening_amount_clp,
                          notes=data.notes.strip(), opened_by_email=request.state.user_email)
    session.add(closure); session.commit(); session.refresh(closure)
    return closure


@router.post("/api/v1/cash/closures/{closure_id}/close", dependencies=[Depends(require_admin)])
def close_cash_closure(closure_id: int, data: CashClosureClose, request: Request,
                       session: Session = Depends(get_session)):
    closure = session.get(CashClosure, closure_id)
    if not closure or closure.status != "open":
        raise HTTPException(404, "Turno de caja abierto no encontrado")
    rows = session.exec(select(CashMovement).where(CashMovement.account_id == closure.account_id,
                        CashMovement.occurred_at >= closure.opened_at, CashMovement.status == "recorded")).all()
    expected = closure.opening_amount_clp + sum(
        row.amount_clp if row.direction in {"income", "transfer_in"} else -row.amount_clp for row in rows)
    closure.status = "closed"; closure.closing_amount_clp = data.closing_amount_clp
    closure.expected_amount_clp = expected; closure.difference_clp = data.closing_amount_clp - expected
    closure.notes = data.notes.strip() or closure.notes; closure.closed_by_email = request.state.user_email
    closure.closed_at = datetime.now(timezone.utc)
    session.add(closure); session.commit(); session.refresh(closure)
    return closure
