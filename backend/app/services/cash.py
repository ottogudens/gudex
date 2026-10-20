"""Central cash-ledger helpers shared by sales, expenses and payment webhooks."""
from sqlmodel import Session, select

from app.models import CashAccount, CashMovement, Payment, Sale


DEFAULT_ACCOUNTS = (
    ("Caja principal", "cash"),
    ("Banco y transferencias", "bank"),
    ("Tarjetas", "card"),
    ("Mercado Pago", "gateway"),
)


def ensure_default_accounts(session: Session) -> None:
    existing = {row.name for row in session.exec(select(CashAccount)).all()}
    for name, kind in DEFAULT_ACCOUNTS:
        if name not in existing:
            session.add(CashAccount(name=name, kind=kind))
    session.flush()


def account_for_payment(session: Session, method: str) -> CashAccount:
    ensure_default_accounts(session)
    name = {
        "cash": "Caja principal",
        "transfer": "Banco y transferencias",
        "card": "Tarjetas",
        "mercado_pago": "Mercado Pago",
        "mercado_pago_checkout": "Mercado Pago",
    }.get(method, "Caja principal")
    return session.exec(select(CashAccount).where(CashAccount.name == name)).one()


def record_sale_payment(session: Session, payment: Payment, sale: Sale,
                        actor_email: str | None = None) -> CashMovement:
    """Create the sole incoming ledger movement for a confirmed payment."""
    existing = session.exec(select(CashMovement).where(CashMovement.payment_id == payment.id)).first()
    if existing:
        return existing
    account = account_for_payment(session, payment.method)
    movement = CashMovement(
        account_id=account.id,
        direction="income",
        amount_clp=payment.amount_clp,
        source_type="sale_payment",
        source_id=sale.id,
        payment_id=payment.id,
        customer_id=sale.customer_id,
        vehicle_id=sale.vehicle_id,
        work_order_id=sale.work_order_id,
        category="venta",
        note=f"Cobro venta {sale.receipt_code}",
        reference=payment.provider_reference,
        created_by_email=actor_email,
        occurred_at=payment.created_at,
    )
    session.add(movement)
    return movement


def backfill_recorded_payments(session: Session) -> int:
    """Idempotently adopt pre-ledger confirmed payments into the central cash book."""
    created = 0
    for payment in session.exec(select(Payment).where(Payment.status == "recorded")).all():
        if session.exec(select(CashMovement).where(CashMovement.payment_id == payment.id)).first():
            continue
        sale = session.get(Sale, payment.sale_id)
        if sale:
            record_sale_payment(session, payment, sale, actor_email="migración")
            created += 1
    return created


def reverse_sale_payment(session: Session, payment: Payment, sale: Sale,
                         reason: str, actor_email: str | None = None) -> CashMovement | None:
    original = session.exec(select(CashMovement).where(CashMovement.payment_id == payment.id)).first()
    if not original:
        return None
    already = session.exec(select(CashMovement).where(CashMovement.reversal_of_id == original.id)).first()
    if already:
        return already
    reversal = CashMovement(
        account_id=original.account_id,
        direction="reversal",
        amount_clp=original.amount_clp,
        source_type="sale_payment_reversal",
        source_id=sale.id,
        customer_id=sale.customer_id,
        vehicle_id=sale.vehicle_id,
        work_order_id=sale.work_order_id,
        category="devolución",
        note=reason[:1000],
        reference=payment.provider_reference,
        reversal_of_id=original.id,
        created_by_email=actor_email,
    )
    session.add(reversal)
    return reversal
