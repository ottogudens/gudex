"""Add technical catalogue attributes to inventory products."""
from alembic import op
import sqlalchemy as sa


revision = "20261021_0033"
down_revision = "20261020_0032"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("product") as batch:
        batch.add_column(sa.Column("manufacturer", sa.String(length=80), nullable=True))
        batch.add_column(sa.Column("product_type", sa.String(length=40), nullable=True))
        batch.add_column(sa.Column("oem_number", sa.String(length=120), nullable=True))
        batch.add_column(sa.Column("equivalent_codes", sa.String(length=1000), nullable=True))
        batch.add_column(sa.Column("technical_specs", sa.String(length=2000), nullable=True))
        batch.add_column(sa.Column("application_notes", sa.String(length=2000), nullable=True))
        batch.add_column(sa.Column("sae_grade", sa.String(length=30), nullable=True))
        batch.add_column(sa.Column("api_spec", sa.String(length=80), nullable=True))
        batch.add_column(sa.Column("acea_spec", sa.String(length=80), nullable=True))
        batch.add_column(sa.Column("oem_approvals", sa.String(length=500), nullable=True))
        batch.add_column(sa.Column("data_source_url", sa.String(length=500), nullable=True))
        batch.add_column(sa.Column("verification_status", sa.String(length=24), nullable=False,
                                  server_default="draft"))


def downgrade():
    with op.batch_alter_table("product") as batch:
        batch.drop_column("verification_status")
        batch.drop_column("data_source_url")
        batch.drop_column("oem_approvals")
        batch.drop_column("acea_spec")
        batch.drop_column("api_spec")
        batch.drop_column("sae_grade")
        batch.drop_column("application_notes")
        batch.drop_column("technical_specs")
        batch.drop_column("equivalent_codes")
        batch.drop_column("oem_number")
        batch.drop_column("product_type")
        batch.drop_column("manufacturer")
