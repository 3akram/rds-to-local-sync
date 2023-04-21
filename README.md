# rds-to-local-sync

This script allows you to easily synchronize your Amazon RDS database with your local development environment. The script first dumps the contents of your RDS database to a local file and then restores the contents of that file to your local development database.

## Requirements

- Docker

## Usage

1. Update the configuration section of the script with your own values.
2. Run the script using `./rds-to-local-sync.sh`.
3. Your local database should now be synchronized with your RDS database.

## Configuration

You will need to pass the following variables to the script:

- `RDS_HOST`: The host of your RDS database.
- `RDS_PORT`: The port of your RDS database.
- `RDS_DBNAME`: The name of your RDS database.
- `RDS_USER`: The user to connect to your RDS database.
- `RDS_PASSWORD`: The password to connect to your RDS database.
- `LOCAL_CONTAINER`: The name of the Docker container running your local database.
- `LOCAL_DBNAME`: The name of your local database.
- `LOCAL_USER`: The user to connect to your local database.
- `LOCAL_PASSWORD`: The password to connect to your local database.
- `LOCAL_PORT`: The port of your local database.

## Help
```sh
./rds-to-local-sync.sh --help 
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
