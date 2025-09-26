# 🐳 Dev Data Stack

A complete Docker-based development data stack with **MySQL**, **PostgreSQL**, **MongoDB**, **Elasticsearch**, **Redis**, **Nginx with TLS**, **Kibana**, **pgAdmin**, and **Adminer**.

Perfect for developers who need multiple databases and management tools running locally with zero configuration.

## ✨ Features

- **🚀 One-command setup** - Everything configured automatically
- **🔄 Hot database loading** - Drop dump files anytime for automatic import
- **🔒 HTTPS ready** - Self-signed TLS certificates included
- **📊 Management UIs** - Web interfaces for all databases
- **💾 Persistent data** - All data survives container restarts
- **🏥 Health monitoring** - Built-in health checks for all services

## 🚀 Quick Start

### Prerequisites
- Ubuntu/Debian system (or WSL2)
- Git installed

### Installation

```bash
# Clone the repository
git clone <your-repo-url> dev_datastack
cd dev_datastack

# Make bootstrap executable and run
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script will:
- ✅ Install Docker & Docker Compose (if missing)
- ✅ Prompt for database credentials (or use defaults)
- ✅ Generate self-signed TLS certificates
- ✅ Configure system settings for Elasticsearch
- ✅ Start all services with health checks

## 📋 Services & Access Points

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| **Your App** (via Nginx) | https://localhost:3000 | - |
| **Kibana** (Elasticsearch UI) | http://localhost:5601 | - |
| **pgAdmin** (PostgreSQL UI) | http://localhost:5050 | admin@example.com / password |
| **Adminer** (Universal DB UI) | http://localhost:8080 | - |

### Direct Database Connections

| Database | Host | Port | Default Credentials |
|----------|------|------|-------------------|
| **MySQL** | localhost | 3306 | root / password |
| **PostgreSQL** | localhost | 5432 | postgres / password |
| **MongoDB** | localhost | 27017 | root / password |
| **Elasticsearch** | localhost | 9200 | - |
| **Redis** | localhost | 6379 | - |

## 💾 Database Import System

The stack includes an automatic import system that watches for new database dumps:

### MySQL
```bash
# Place files in input/mysql/
cp mydb__backup.sql input/mysql/
# Database 'mydb' will be created automatically
```

### PostgreSQL
```bash
# SQL dumps
cp myapp__dump.sql input/postgres/

# Binary dumps
cp myapp__backup.dump input/postgres/
```

### MongoDB
```bash
# Archive files
cp mydata.archive input/mongo/

# Directory dumps
cp -r mydatabase_dump input/mongo/
```

**💡 Pro Tip**: Database names are automatically extracted from filenames (everything before `__`).

## 🛠️ Common Commands

### Stack Management
```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs for all services
docker compose logs -f

# View logs for specific service
docker compose logs -f mysql

# Check service status
docker compose ps

# Restart a specific service
docker compose restart mysql
```

### Database Operations
```bash
# Access MySQL shell
docker compose exec mysql mysql -uroot -ppassword

# Access PostgreSQL shell
docker compose exec postgres psql -U postgres

# Access MongoDB shell
docker compose exec mongo mongosh -u root -p password

# Access Redis CLI
docker compose exec redis redis-cli
```

### Troubleshooting
```bash
# Check import logs
docker compose logs -f db-importer

# Restart importer service
docker compose restart db-importer

# View Elasticsearch logs
docker compose logs -f elasticsearch

# Check Nginx access logs
tail -f nginx/logs/access.log
```

## 🗂️ Project Structure

```
dev_datastack/
├── bootstrap.sh          # Interactive setup script
├── docker-compose.yml    # Service definitions
├── .env                  # Environment variables
├── input/                # Database dump files
│   ├── mysql/           # MySQL .sql/.sql.gz files
│   ├── postgres/        # PostgreSQL .sql/.sql.gz/.dump files
│   └── mongo/           # MongoDB directories/.archive files
├── data/                 # Persistent database storage
├── nginx/               # Nginx configuration & certificates
├── importer/            # Database import logic
└── kibana/              # Kibana configuration
```

## ⚙️ Configuration

### Environment Variables
Edit `.env` to customize:
```bash
# Database credentials
MYSQL_ROOT_PASSWORD=password
POSTGRES_PASSWORD=password
MONGO_INITDB_ROOT_PASSWORD=password

# pgAdmin
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=password
```

### Custom Application
The Nginx service is configured to proxy `https://localhost:3000` to your application running on `http://localhost:3000` on the host machine.

## 🔧 Advanced Usage

### Adding Custom Databases
```bash
# Create additional databases
docker compose exec mysql mysql -uroot -ppassword -e "CREATE DATABASE newdb;"
docker compose exec postgres psql -U postgres -c "CREATE DATABASE newdb;"
```

### Backup Data
```bash
# Backup MySQL
docker compose exec mysql mysqldump -uroot -ppassword mydb > backup.sql

# Backup PostgreSQL
docker compose exec postgres pg_dump -U postgres mydb > backup.sql

# Backup MongoDB
docker compose exec mongo mongodump --uri="mongodb://root:password@localhost/mydb"
```

### Custom SSL Certificates
Replace the self-signed certificates in `nginx/certs/` with your own:
```bash
cp your-cert.pem nginx/certs/localhost.crt
cp your-key.pem nginx/certs/localhost.key
docker compose restart nginx
```

## 🚨 System Requirements

- **Memory**: At least 4GB RAM (Elasticsearch needs 1GB heap)
- **Disk**: 2GB+ free space for containers and data
- **OS**: Ubuntu/Debian (bootstrap script specific)
- **Ports**: 3000, 3306, 5050, 5432, 5601, 6379, 8080, 9200, 27017

## 🛟 Troubleshooting

### Common Issues

**Elasticsearch won't start:**
```bash
# Increase virtual memory map count
sudo sysctl -w vm.max_map_count=262144
# Or run bootstrap.sh again
```

**Permission denied on bootstrap.sh:**
```bash
chmod +x bootstrap.sh
```

**Port conflicts:**
```bash
# Check what's using ports
sudo netstat -tulpn | grep :3306
# Stop conflicting services or modify docker-compose.yml
```

**Database import not working:**
```bash
# Check importer logs
docker compose logs -f db-importer

# Manually trigger import
docker compose exec db-importer /app/import.sh
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes with `./bootstrap.sh`
4. Submit a pull request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

---

**Made with ❤️ for developers who need databases fast** 🚀