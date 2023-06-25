# PostgSail ERD
The Entity-Relationship Diagram (ERD) provides a graphical representation of database tables, columns, and inter-relationships. ERD can give sufficient information for the database administrator to follow when developing and maintaining the database.

## A global overview
![API Schema](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/ERD/postgsail.pgerd.png "API Schema")

## Further
There is 3 main schemas:
- API Schema ERD
    - tables
      - metrics
      - logbook
      - ...
    - functions
      - ...
![API Schem](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/ERD/signalk - api.png "API Schema")

- Auth Schema ERD
  - tables
    - accounts
    - vessels
    - ...
  - functions
    - ...
![Auth Schema](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/ERD/signalk - auth.png "Auth Schema")

- Public Schema ERD
  - tables
    - app_settings
    - tpl_messages
    - ...
  - functions
    - ...
![Public Schema](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/ERD/signalk - public.png "Public Schema")

