# Terraform + Database Reliability

A DevOps project demonstrating reusable AWS infrastructure with Terraform and PostgreSQL database.

## Architecture

```text
Internet
   |
   v
Application Load Balancer (public subnets)
   |
   v
ECS Fargate service (private application subnets)
   |
   v
Amazon RDS PostgreSQL (isolated private database subnets)

Local database workflow:
Docker Compose -> PostgreSQL -> migrations -> seed data -> indexes
                                      |
                                      +-> backup.sh -> timestamped custom-format dump
                                      +-> restore.sh -> fresh restore database
```

The Terraform configuration is infrastructure-as-code only. No AWS deployment is required for this assessment. The local database workflow is independent of AWS.

## Repository layout

```text
.
├── .github/workflows/infra-ci.yml
├── infra/
│   ├── modules/
│   │   ├── network/
│   │   ├── ecs/
│   │   └── rds/
│   └── envs/
│       ├── dev/
|              ├── backend.hcl
|              ├── terraform.tfvars  
│       └── prod/
|              ├── backend.hcl
|              ├── terraform.tfvars
├── database/
│   ├── migrations/001_init.sql
│   └── seed/001_seed.sql
├── scripts/
│   ├── backup.sh
│   └── restore.sh
├── .env.example
├── docker-compose.yml
└── README.md
```

## Prerequisites

- Docker Engine and Docker Compose v2
- Terraform 1.6 or later (for infrastructure validation)
- Git
- Bash


## 1. Run the local database

From the repository root:

Set the environments variables as mentioned in .env.example
```bash
cp .env.example .env
```

```bash
docker compose up -d
docker compose ps
```

Wait until PostgreSQL reports healthy:

```bash
source .env
docker compose exec -T db pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}
```

The database uses a named Docker volume, so data survives container recreation. The credentials are for local assessment use only and must not be reused in production.

## 2. Apply migration and seed data

The SQL files are mounted into `/docker-entrypoint-initdb.d`. PostgreSQL executes them automatically the first time the data volume is initialized.

```bash
docker compose logs db
```

Verify the schema and row counts:

```bash
docker compose exec -T db psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c '\dt'
docker compose exec -T db psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c \
  "SELECT COUNT(*) AS booking_count, COUNT(DISTINCT city) AS cities, COUNT(DISTINCT org_id) AS organizations FROM hotel_bookings;"
docker compose exec -T db psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c \
  "SELECT COUNT(*) AS event_count FROM booking_events;"
```

Expected: at least 100 bookings, multiple cities and organizations, and booking events for a subset of bookings.

To re-run initialization from a clean database (this deletes local database data):

```bash
docker compose down -v
docker compose up -d
```

## 3. Query optimization

Target query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

Migration `001_init.sql` creates this composite B-tree index:

```sql
CREATE INDEX idx_hotel_bookings_city_created_org_status
ON hotel_bookings (city, created_at, org_id, status)
INCLUDE (amount);
```

Why this index:
- `city` is an equality predicate, so it is first.
- `created_at` is a range predicate, so it follows the equality column.
- `org_id` and `status` are included after the filter columns to make the grouping values available from the index.
- `amount` is an included column so PostgreSQL may be able to perform an index-only scan without storing it as another key column.

The planner decides whether an index scan is cheaper than a sequential scan based on table size, statistics, and selectivity. The index does not guarantee an index-only scan in every execution.

Inspect the plan:

```bash
docker compose exec -T db psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c \
  "EXPLAIN (ANALYZE, BUFFERS) SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status;"
```

## 4. Backup

Create a timestamped PostgreSQL custom-format dump:

```bash
./scripts/backup.sh
```

By default, dumps are written to `backups/`. The script prints the created file path. The backup directory is intentionally ignored by Git.

## 5. Restore into a fresh database

Restore the latest backup into a separate database named `bookingdb_restore`:

```bash
./scripts/restore.sh
```

Or specify a particular dump and target database:

```bash
./scripts/restore.sh backups/bookingdb_YYYYMMDD_HHMMSS.dump bookingdb_restore
```

The restore script creates the target database if needed, terminates existing connections to that target, and restores the dump with `pg_restore --no-owner --no-privileges`.

Verify that the restore worked:

```bash
docker compose exec -T db psql -U ${POSTGRES_USER} -d bookingdb_restore -c \
  "SELECT COUNT(*) AS booking_count FROM hotel_bookings;"
docker compose exec -T db psql -U ${POSTGRES_USER} -d bookingdb_restore -c \
  "SELECT COUNT(*) AS event_count FROM booking_events;"
docker compose exec -T db psql -U ${POSTGRES_USER} -d bookingdb_restore -c \
  "SELECT city, status, COUNT(*) FROM hotel_bookings GROUP BY city, status ORDER BY city, status;"
```

Compare the source and restored counts:

```bash
for database in bookingdb bookingdb_restore; do
  printf '%s: ' "$database"
  docker compose exec -T db psql -U appuser -d "$database" -Atc \
    "SELECT (SELECT COUNT(*) FROM hotel_bookings) || ' bookings / ' || (SELECT COUNT(*) FROM booking_events) || ' events';"
done
```

The two databases should return the same counts.

## 6. Terraform environments

Terraform code is under `infra/`. The network, ECS, and RDS resources are reusable modules. Dev and Prod have separate root configurations, variables, sizing, state paths, backup retention, and deletion-protection settings.

| Setting | Dev | Prod |
|---|---:|---:|
| ECS desired tasks | 1 | 2 |
| ECS CPU / memory | 256 / 512 MiB | 512 / 1024 MiB |
| RDS instance | db.t3.micro | db.t3.small |
| RDS allocated storage | 20 GiB | 50 GiB |
| Backup retention | 1 day | 14 days |
| Deletion protection | false | true |
| Multi-AZ | false | true |

Each environment uses a local backend with a distinct state file so the examples can be initialized without creating an S3 bucket. For a team/production deployment, replace the local backend with an S3 backend and enable bucket versioning, encryption, and DynamoDB-based state locking (or the supported S3 lockfile mechanism for your Terraform version). Never share a state file between environments.

### Format, initialize, validate, and plan

Run commands by referencing dev or prod folder:

```bash
terraform fmt -recursive infra
cd infra/
terraform init -backend-config=envs/dev/backend.hcl
terraform validate
terraform plan -refresh=false
```

For production:

```bash
terraform init -backend-config=envs/prod/backend.hcl
terraform validate
terraform plan -refresh=false
```

The AWS provider is configured to skip account/credential preflight checks for plan-only review. This does not deploy resources and does not make AWS credentials unnecessary for an actual apply. A real apply requires valid AWS credentials, an available AWS region, and review of costs and quotas.


## 7. GitHub Actions

`.github/workflows/infra-ci.yml` runs on pull requests and pushes to the main branch. It:
- Checks formatting.
- Initializes each environment without a remote backend.
- Validates the configuration.
- Creates a plan with `-refresh=false`.
- Uploads each plan text file as a workflow artifact.

## Assessment verification checklist

- [ ] `docker compose up -d` succeeds and PostgreSQL is healthy.
- [ ] Migrations and seed data are loaded.
- [ ] Booking count is at least 100.
- [ ] Query plan can be inspected with `EXPLAIN (ANALYZE, BUFFERS)`.
- [ ] `./scripts/backup.sh` creates a timestamped dump.
- [ ] `./scripts/restore.sh` restores into a fresh database.
- [ ] Source and restored row counts match.
- [ ] `terraform fmt -recursive` succeeds.
- [ ] `terraform init`, `terraform validate`, and `terraform plan -refresh=false` are reviewed for both environments.
- [ ] GitHub Actions workflow runs successfully on a pull request.
