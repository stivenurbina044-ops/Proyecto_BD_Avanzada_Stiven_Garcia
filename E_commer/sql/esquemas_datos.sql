-- =====================================================
-- 01_Esquema_y_Datos.sql
-- Base de datos, tablas y datos iniciales
-- =====================================================
CREATE DATABASE IF NOT EXISTS E_commerce CHARACTER SET utf8mb4;
USE E_commerce;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS producto_vistas, detalles_ventas, detalle_ventas, log_cambios_precio,
                     ventas, productos, clientes, categorias, proveedores;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE categorias (
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT
);

CREATE TABLE proveedores (
    id_proveedor INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    email_contacto VARCHAR(100) UNIQUE,
    telefono_contacto VARCHAR(20)
);

CREATE TABLE productos (
    id_producto INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL CHECK (precio > 0),
    costo DECIMAL(10,2) NOT NULL CHECK (costo >= 0),
    stock INT NOT NULL DEFAULT 0 CHECK (stock >= 0),
    stock_minimo INT NOT NULL DEFAULT 5,
    sku VARCHAR(50) NOT NULL UNIQUE,
    id_categoria INT NULL,               -- NULL permitido: el trigger asigna 'General'
    id_proveedor INT NOT NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion DATETIME NULL,
    fecha_eliminacion DATETIME NULL,     -- borrado lógico
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria),
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
);

CREATE TABLE clientes (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    contrasena VARCHAR(255) NOT NULL,
    direccion_envio VARCHAR(255),
    ciudad VARCHAR(100),
    fecha_nacimiento DATE NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_gastado DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    fecha_ultima_compra DATETIME NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE ventas (
    id_venta INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    fecha_venta TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    estado VARCHAR(30) NOT NULL DEFAULT 'Pendiente de Pago'
        CHECK (estado IN ('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado')),
    total DECIMAL(10,2) NOT NULL DEFAULT 0.00 CHECK (total >= 0),
    id_sucursal INT NOT NULL DEFAULT 1,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

CREATE TABLE detalles_ventas (
    id_detalle INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_unitario_congelado DECIMAL(10,2) NOT NULL CHECK (precio_unitario_congelado > 0),
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta) ON DELETE CASCADE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

CREATE TABLE producto_vistas (
    id_vista INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    fecha_vista DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
);

-- ---------------- DATOS INICIALES ----------------
INSERT INTO categorias (nombre, descripcion) VALUES
('General', 'Productos sin categoria especifica'),
('Electronica', 'Dispositivos y accesorios electronicos'),
('Hogar', 'Articulos para el hogar'),
('Deportes', 'Equipos y accesorios deportivos'),
('Libros', 'Libros y material de lectura');

INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TecnoAndes', 'ventas@tecnoandes.example.com', '6070000001'),
('HogarCol', 'contacto@hogarcol.example.com', '6070000002'),
('DeporMax', 'info@depormax.example.com', '6070000003'),
('Editorial Santander', 'pedidos@editorialsantander.example.com', '6070000004');

INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor) VALUES
('Audifonos Bluetooth', 'Audifonos inalambricos con cancelacion de ruido', 120000, 70000, 40, 'SKU-ELE-AUDI-101', 2, 1),
('Mouse Inalambrico', 'Mouse ergonomico 2.4 GHz', 65000, 35000, 60, 'SKU-ELE-MOUS-102', 2, 1),
('Teclado Mecanico', 'Teclado mecanico retroiluminado', 210000, 130000, 25, 'SKU-ELE-TECL-103', 2, 1),
('Monitor 24 Pulgadas', 'Monitor Full HD IPS', 780000, 520000, 12, 'SKU-ELE-MONI-104', 2, 1),
('Lampara LED Escritorio', 'Lampara con brillo regulable', 55000, 28000, 50, 'SKU-HOG-LAMP-105', 3, 2),
('Cafetera Electrica', 'Cafetera de goteo 12 tazas', 190000, 120000, 8, 'SKU-HOG-CAFE-106', 3, 2),
('Juego de Sabanas', 'Sabanas de algodon doble', 95000, 50000, 30, 'SKU-HOG-JUEG-107', 3, 2),
('Balon de Futbol', 'Balon profesional n5', 70000, 40000, 45, 'SKU-DEP-BALO-108', 4, 3),
('Pesas Ajustables', 'Par de mancuernas ajustables', 260000, 170000, 4, 'SKU-DEP-PESA-109', 4, 3),
('Tapete de Yoga', 'Tapete antideslizante 6 mm', 60000, 30000, 35, 'SKU-DEP-TAPE-110', 4, 3),
('Libro de Cocina Colombiana', 'Recetas tradicionales', 48000, 25000, 20, 'SKU-LIB-LIBR-111', 5, 4),
('Mochila Antirrobo', 'Mochila con puerto USB', 135000, 80000, 3, 'SKU-GEN-MOCH-112', 1, 1);

INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio, ciudad, fecha_nacimiento, fecha_registro) VALUES
('Laura', 'Gomez', 'laura.gomez@example.com', '$2b$10$hashdeejemplo000000000000000000000000000000000001', 'Cra 27 #45-10', 'Bucaramanga', '1990-10-03', '2026-01-05 10:00:00'),
('Carlos', 'Rojas', 'carlos.rojas@example.com', '$2b$10$hashdeejemplo000000000000000000000000000000000002', 'Calle 72 #10-34', 'Bogota', '1985-05-21', '2026-01-08 14:30:00'),
('Maria', 'Diaz', 'maria.diaz@example.com', '$2b$10$hashdeejemplo000000000000000000000000000000000003', 'Cra 43A #1-50', 'Medellin', '1992-02-14', '2026-02-01 09:15:00'),
('Andres', 'Pardo', 'andres.pardo@example.com', '$2b$10$hashdeejemplo000000000000000000000000000000000004', 'Calle 35 #19-20', 'Bucaramanga', '1988-09-29', '2026-02-20 16:45:00'),
('Sofia', 'Herrera', 'sofia.herrera@example.com', '$2b$10$hashdeejemplo000000000000000000000000000000000005', 'Av 6N #23-12', 'Cali', '1995-12-08', '2026-03-15 11:20:00'),
('Julian', 'Vargas', 'julian.vargas@example.com', '$2b$10$hashdeejemplo000000000000000000000000000000000006', 'Cra 25 #30-08', 'Floridablanca', '1991-07-17', '2026-06-10 08:05:00');

INSERT INTO ventas (id_cliente, fecha_venta, estado, total) VALUES
(1, '2026-01-10 10:15:00', 'Entregado', 250000),
(2, '2026-01-15 15:40:00', 'Entregado', 780000),
(1, '2026-02-03 09:20:00', 'Entregado', 265000),
(3, '2026-02-14 20:05:00', 'Entregado', 380000),
(4, '2026-03-02 11:30:00', 'Enviado', 200000),
(2, '2026-03-20 18:10:00', 'Entregado', 185000),
(5, '2026-04-08 13:25:00', 'Cancelado', 260000),
(1, '2026-05-12 10:50:00', 'Entregado', 230000),
(3, '2026-06-18 16:45:00', 'Entregado', 156000),
(6, '2026-07-22 12:00:00', 'Procesando', 200000),
(4, '2026-08-30 19:30:00', 'Pendiente de Pago', 210000),
(2, '2026-09-15 09:10:00', 'Entregado', 125000);

INSERT INTO detalles_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 120000), (1, 2, 2, 65000),
(2, 4, 1, 780000),
(3, 3, 1, 210000), (3, 5, 1, 55000),
(4, 6, 1, 190000), (4, 7, 2, 95000),
(5, 8, 2, 70000),  (5, 10, 1, 60000),
(6, 1, 1, 120000), (6, 2, 1, 65000),
(7, 9, 1, 260000),
(8, 1, 1, 120000), (8, 5, 2, 55000),
(9, 11, 2, 48000), (9, 10, 1, 60000),
(10, 12, 1, 135000), (10, 2, 1, 65000),
(11, 3, 1, 210000),
(12, 5, 1, 55000), (12, 8, 1, 70000);

INSERT INTO producto_vistas (id_producto) VALUES
(1),(1),(1),(1),(2),(2),(3),(3),(4),(4),(4),(5),(5),(6),(8),(9),(9),(9),(9),(10),(11),(12),(12);
INSERT INTO producto_vistas (id_producto) VALUES (7);
-- Multiplica las vistas x4 para que las conversiones de ejemplo sean realistas
INSERT INTO producto_vistas (id_producto) SELECT id_producto FROM producto_vistas;
INSERT INTO producto_vistas (id_producto) SELECT id_producto FROM producto_vistas;

-- Acumulados de clientes (los triggers se crean después, en el script 05)
UPDATE clientes c
SET total_gastado = COALESCE((SELECT SUM(v.total) FROM ventas v
                              WHERE v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'), 0),
    fecha_ultima_compra = (SELECT MAX(v.fecha_venta) FROM ventas v
                           WHERE v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado');