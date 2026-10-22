"""Add supplier registry and reviewable inventory purchase receipts."""
from alembic import op
import sqlalchemy as sa


revision = "20261022_0034"
down_revision = "20261021_0033"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "supplier",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("rut", sa.String(length=24), nullable=True, unique=True),
        sa.Column("name", sa.String(length=180), nullable=False),
        sa.Column("email", sa.String(length=254), nullable=True),
        sa.Column("phone", sa.String(length=40), nullable=True),
        sa.Column("address", sa.String(length=300), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_supplier_rut", "supplier", ["rut"], unique=True)
    op.create_index("ix_supplier_name", "supplier", ["name"], unique=False)
    op.create_table(
        "purchasereceipt",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("code", sa.String(length=32), nullable=False, unique=True),
        sa.Column("supplier_id", sa.Integer(), sa.ForeignKey("supplier.id"), nullable=True),
        sa.Column("document_type", sa.String(length=40), nullable=False),
        sa.Column("folio", sa.String(length=80), nullable=True),
        sa.Column("issue_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("net_amount_clp", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("tax_amount_clp", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("total_amount_clp", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="review"),
        sa.Column("source_format", sa.String(length=12), nullable=False),
        sa.Column("original_filename", sa.String(length=255), nullable=False),
        sa.Column("storage_path", sa.String(length=500), nullable=False),
        sa.Column("extraction_note", sa.String(length=2000), nullable=True),
        sa.Column("cash_movement_id", sa.Integer(), sa.ForeignKey("cashmovement.id"), nullable=True),
        sa.Column("created_by_email", sa.String(length=254), nullable=True),
        sa.Column("reviewed_by_email", sa.String(length=254), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("applied_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_purchasereceipt_code", "purchasereceipt", ["code"], unique=True)
    op.create_index("ix_purchasereceipt_supplier_id", "purchasereceipt", ["supplier_id"], unique=False)
    op.create_table(
        "purchasereceiptline",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("purchase_receipt_id", sa.Integer(), sa.ForeignKey("purchasereceipt.id"), nullable=False),
        sa.Column("product_id", sa.Integer(), sa.ForeignKey("product.id"), nullable=True),
        sa.Column("supplier_code", sa.String(length=120), nullable=True),
        sa.Column("description", sa.String(length=300), nullable=False),
        sa.Column("quantity", sa.Float(), nullable=False),
        sa.Column("unit_cost_clp", sa.Integer(), nullable=False),
        sa.Column("line_total_clp", sa.Integer(), nullable=False),
        sa.Column("match_status", sa.String(length=24), nullable=False, server_default="unmatched"),
        sa.Column("notes", sa.String(length=500), nullable=True),
    )
    op.create_index("ix_purchasereceiptline_purchase_receipt_id", "purchasereceiptline", ["purchase_receipt_id"], unique=False)
    op.create_index("ix_purchasereceiptline_product_id", "purchasereceiptline", ["product_id"], unique=False)


def downgrade():
    op.drop_table("purchasereceiptline")
    op.drop_table("purchasereceipt")
    op.drop_table("supplier")
