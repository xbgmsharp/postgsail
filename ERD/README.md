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
![API Schema](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/ERD/signalk%20-%20api.png)

- Auth Schema ERD
  - tables
    - accounts
    - vessels
    - ...
  - functions
    - ...
![Auth Schema](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/ERD/signalk%20-%20auth.png "Auth Schema")

- Public Schema ERD
  - tables
    - app_settings
    - tpl_messages
    - ...
  - functions
    - ...
![Public Schema](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/ERD/signalk%20-%20public.png "Public Schema")

