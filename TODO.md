# To Do

## Terraform

- [x] Warehouse
- [x] Roles
- [x] Role grants
- [x] Production config
- [ ] Update Terraform/README.md

## Data Model

- [x] Design conceptual, logical, physical data model for earthquakes
- [x] Documentation

## Ingestion

- [x] Create ingestion audit table to be able to store watermark
- [x] Create python ingestion scripts
- [x] Split ingestion scripts into individual envs
- [x] Configure ingestion scripts with CI/CD

## dbt

- [x] Model data
- [x] Build models
- [x] Testing strategy: include relationships tests for dims -> fact
- [x] Create views in presentation layer
- [x] CI/CD across envs
- [x] Create a run-operation macro to execute the ingestion_metadata_ddl scripts per dbt run
- [x] Create a new service account for running the dbt jobs with. Engineer is fine as a placeholder for now.
- [x] Handle null foreign keys
- [x] Remove US state code seed as unused
