CREATE DATABASE IF NOT EXISTS cloudha_db;

USE cloudha_db;

CREATE TABLE IF NOT EXISTS productos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    precio DECIMAL(10,2) NOT NULL,
    existencia INT NOT NULL DEFAULT 0,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO productos (nombre, precio, existencia)
SELECT 'Producto de prueba', 150.00, 10
WHERE NOT EXISTS (
    SELECT 1 FROM productos
);