# PostgreSQL Sink Connectors (Scaffold)

This directory is a placeholder for PostgreSQL sink connector configurations.

## Intended Structure

Each connector will be defined as a separate YAML file following the pattern:
- `connector-name.yaml` - Connector configuration
- `connector-name.env` - Environment-specific overrides

## What Remains to be Filled In

1. **Connector Definitions**: Concrete Kafka Connect configurations for sink topics
2. **Environment Overrides**: Per-environment connection strings and settings
3. **Deployment Scripts**: Terraform resources to deploy connectors via the Confluent API

## Current Status

- Catalog structure established
- Connector configurations deferred (requires Connect cluster reference)
- Deployment automation deferred

## Notes

- Connectors are deployed via Confluent Cloud API, not direct database access
- Each connector maps to specific database tables in the analytics schema
- Schema evolution policies will be defined per connector
