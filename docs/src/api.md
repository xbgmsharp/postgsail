# API Documentation

## Overview

PostgSail exposes its PostgreSQL database through a RESTful API using PostgREST, which serves as the primary interface for all client interactions. The API supports three main authentication roles that determine access permissions and available endpoints.

## Authentication

The API uses JWT (JSON Web Token) authentication with role-based switching. The JWT token contains claims that set session variables used by Row Level Security policies:

- `vessel.id` - Current vessel identifier
- `user.email` - Current user email  
- `user.id` - Current user identifier

### API Roles

#### api_anonymous
Unauthenticated access with read-only permissions on public data for public access when enable

#### user_role
Authenticated web users with full access to their vessel data.

#### vessel_role
SignalK plugin data ingestion with insert/update permissions.

#### mcp_role
Authenticated web users with read-only access to their vessel data via an Large language model.

## API Endpoints

### Base URL
```
http://localhost:3000
```

### Authentication Examples

**Anonymous access:**
```bash
curl http://localhost:3000/
```

**User role access:**
```bash
curl http://localhost:3000/ -H 'Authorization: Bearer my_token_from_login_or_signup_fn'
```

**Vessel role access:**
```bash
curl http://localhost:3000/ -H 'Authorization: Bearer my_token_from_register_vessel_fn'
```

### Key Endpoints by Role

#### Authentication Functions
- `POST /rpc/login` - User authentication 
- `POST /rpc/signup` - User registration
- `POST /rpc/register_vessel` - Vessel registration

#### Data Tables (user_role and vessel_role)
- `GET /metrics` - Time-series telemetry data
- `GET /logbook` - Trip records with trajectories
- `GET /stays` - Mooring/anchoring periods
- `GET /moorages` - Named locations
- `GET /metadata` - Vessel metadata including configuration

#### Views (user_role)
- `GET /logs_view` - Enriched logbook data
- `GET /log_view` - Details logbook data
- `GET /moorages_view` - Enriched moorage data
- `GET /moorage_view` - Details moorage data
- `GET /stays_view` - Enriched Stays data
- `GET /stay_view` - Details Stay data
- `GET /vessels_view` - Vessel data
- `GET /monitoring_view` - System monitoring data

#### RPC Functions
- `POST /rpc/settings_fn` - User preferences
- `POST /rpc/update_user_preferences_fn` - Update preferences
- `POST /rpc/versions_fn` - System version information
- `POST /rpc/vessel_fn` - Vessel details

## OpenAPI Documentation

The OpenAPI specification is dynamically generated based on the authenticated role's permissions. Access the interactive documentation at:

`https://petstore.swagger.io/?url=https://raw.githubusercontent.com/xbgmsharp/postgsail/main/openapi.json`

Other applications can also use the [PostgSAIL API](https://petstore.swagger.io/?url=https://raw.githubusercontent.com/xbgmsharp/postgsail/main/openapi.json).

The available endpoints and operations in the OpenAPI spec will vary depending on the JWT role used to access `/`.

## Public Access

Anonymous users can access specific public data when vessel owners have enabled public sharing.

## Configuration

The PostgREST service is configured via environment variables:
- `PGRST_DB_SCHEMA: api` - Default schema
- `PGRST_DB_ANON_ROLE: api_anonymous` - Anonymous role
- `PGRST_DB_PRE_REQUEST: public.check_jwt` - JWT validation function
- `PGRST_JWT_SECRET` - JWT signing secret

## Notes

- The API runs on port 3000 by default
- All data access is controlled by Row Level Security policies based on vessel ownership
- The SignalK plugin uses vessel_role for continuous data ingestion
- Rate limiting and connection limits are enforced per role
