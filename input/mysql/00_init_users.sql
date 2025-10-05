-- MySQL initialization script
-- This script configures authentication and creates necessary users
-- Executed automatically on container startup if database is fresh

-- Change root authentication to mysql_native_password for compatibility
ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'password';
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';

-- Create pyr user with mysql_native_password authentication
CREATE USER IF NOT EXISTS 'pyr'@'%' IDENTIFIED WITH mysql_native_password BY 'pyr';

-- Grant all privileges on pyr_partylite_dev database to pyr user
GRANT ALL PRIVILEGES ON pyr_partylite_dev.* TO 'pyr'@'%';

-- Apply privilege changes
FLUSH PRIVILEGES;
