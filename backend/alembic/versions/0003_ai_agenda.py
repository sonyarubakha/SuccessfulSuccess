"""Store edited meeting agendas and original AI suggestions.

Revision ID: 0003
Revises: 0002
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "meetings",
        sa.Column("agenda", postgresql.JSONB(), nullable=True),
    )
    op.add_column(
        "meetings",
        sa.Column("ai_suggestion", postgresql.JSONB(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("meetings", "ai_suggestion")
    op.drop_column("meetings", "agenda")
