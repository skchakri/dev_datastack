// MongoDB initialization script
// This script updates the root user with additional roles
// Executed automatically on container startup if placed in /docker-entrypoint-initdb.d/

db = db.getSiblingDB('admin');

// Update root user roles to include full admin access and read/write across all databases
db.updateUser("root", {
  roles: [
    { role: "root", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" }
  ]
});

print("MongoDB root user roles updated successfully");
