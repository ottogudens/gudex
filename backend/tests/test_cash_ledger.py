from types import SimpleNamespace

from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.routers.cash import (cash_summary, create_cash_expense,
                              create_cash_transfer, list_cash_accounts,
                              open_cash_closure)
from app.schemas import CashClosureOpen, CashExpenseCreate, CashTransferCreate


def _request():
    return SimpleNamespace(state=SimpleNamespace(user_email="admin@prueba.cl"))


def test_expenses_and_transfers_share_the_central_cash_ledger():
    create_db_and_tables()
    with Session(engine) as session:
        accounts = list_cash_accounts(session)
        assert len(accounts) >= 2
        cash = next(account for account in accounts if account.name == "Caja principal")
        bank = next(account for account in accounts if account.name == "Banco y transferencias")

        expense = create_cash_expense(CashExpenseCreate(account_id=cash.id, amount_clp=3500,
            category="insumos", note="Compra de guantes"), _request(), session)
        assert expense["direction"] == "expense"
        transfer = create_cash_transfer(CashTransferCreate(from_account_id=cash.id,
            to_account_id=bank.id, amount_clp=10000, note="Depósito diario"), _request(), session)
        assert transfer["outgoing"]["amount_clp"] == 10000
        assert transfer["incoming"]["amount_clp"] == 10000

        closure = open_cash_closure(CashClosureOpen(account_id=cash.id, opening_amount_clp=20000),
                                    _request(), session)
        assert closure.status == "open"
        summary = cash_summary(session=session)
        assert summary["expense_clp"] >= 3500
        assert any(row["account"].name == "Banco y transferencias" for row in summary["accounts"])
