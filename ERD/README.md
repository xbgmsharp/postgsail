# PostgSail ERD
The Entity-Relationship Diagram (ERD) provides a graphical representation of database tables, columns, and inter-relationships. ERD can give sufficient information for the database administrator to follow when developing and maintaining the database.

## A global overview
![API Schema](https://github.com/xbgmsharp/postgsail/ERD/postgsail.pgerd.png?raw=true "API Schema")

## Further
There is 3 main schemas:
- API Schema ERD
    - tables
      - metrics
      - logbook
      - ...
    - functions
      - ...
![API Schem](https://github.com/xbgmsharp/postgsail/ERD/ERD_schema_api.png?raw=true "API Schema")

- Auth Schema ERD
  - tables
    - accounts
    - vessels
    - ...
  - functions
    - ...
![Auth Schema](https://github.com/xbgmsharp/postgsail/ERD/ERD_schema_auth.png?raw=true "Auth Schema")

- Public Schema ERD
  - tables
    - app_settings
    - tpl_messages
    - ...
  - functions
    - ...
![Public Schema](https://github.com/xbgmsharp/postgsail/ERD/ERD_schema_public.png?raw=true "Public Schema")

