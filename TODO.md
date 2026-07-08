# To Do

## Terraform

- [x] Warehouse
- [x] Roles
- [x] Role grants
- [x] Production config

## Data Model

- [ ] Design conceptual, logical, physical data model for earthquakes
- [ ] Documentation

## Ingestion

- [ ] Create ingestion audit table to be able to store watermark
- [ ] Create python ingestion scripts
- [ ] Automate with a task - ad hoc runs
- [ ] Split ingestion scripts into individual envs
- [ ] Configure ingestion scripts with CI/CD

## dbt

- [ ] Model data
- [ ] Build models
- [ ] Testing strategy
- [ ] Create views in presentation layer
- [ ] CI/CD across envs
- [ ] Create a run-operation macro to execute the ingestion_metadata_ddl scripts per dbt run
- [ ] Create a new service account for running the dbt jobs with. Engineer is fine as a placeholder for now.
- [ ] Handle null foreign keys
