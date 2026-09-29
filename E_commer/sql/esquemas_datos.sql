-- Esquemas y datos

CREATE DATABASE IF NOT EXISTS E_commerce;
USE E_commerce;

USE E_commerce;

-- Desactivar verificación de llaves foráneas para permitir el DROP
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS detalles_ventas;
DROP TABLE IF EXISTS detalle_ventas;
DROP TABLE IF EXISTS log_cambios_precio;
DROP TABLE IF EXISTS ventas;
DROP TABLE IF EXISTS productos;
DROP TABLE IF EXISTS clientes;
DROP TABLE IF EXISTS categorias;

-- Reactivar verificación de llaves foráneas
SET FOREIGN_KEY_CHECKS = 1;


CREATE TABLE IF NOT EXISTS categorias (
	id_categoria INT AUTO_INCREMENT PRIMARY KEY,
	nombre VARCHAR (100) NOT NULL UNIQUE,
	descripcion TEXT
);

CREATE TABLE IF NOT EXISTS proveedores (
	id_proveedor INT AUTO_INCREMENT PRIMARY KEY,
	nombre VARCHAR (100) NOT NULL UNIQUE,
	email_contacto VARCHAR (100) UNIQUE,
	telefono_contacto VARCHAR (20) 
);

CREATE TABLE IF NOT EXISTS productos (
	id_producto INT AUTO_INCREMENT PRIMARY KEY,
	nombre VARCHAR (100) NOT NULL UNIQUE,
	descripcion TEXT,
	precio DECIMAL (10, 2) NOT NULL CHECK (precio > 0),
	costo DECIMAL (10, 2) NOT NULL CHECK (costo >= 0), 
	stock INT NOT NULL DEFAULT 0 CHECK (stock >= 0),
	sku VARCHAR(50) NOT NULL UNIQUE,
	
	id_categoria INT NOT NULL,
	id_proveedor INT NOT NULL,
	
	fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	activo BOOLEAN NOT NULL DEFAULT TRUE,

	FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria),
	FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
);

CREATE TABLE IF NOT EXISTS clientes (
	id_cliente INT AUTO_INCREMENT PRIMARY KEY,
	nombre VARCHAR (100) NOT NULL,       
	apellido VARCHAR (100) NOT NULL,   
	email VARCHAR (100) NOT NULL UNIQUE,
	contraseña VARCHAR (225) NOT NULL,
	direccion_envio VARCHAR (100),
	fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ventas (
	id_venta INT AUTO_INCREMENT PRIMARY KEY,
	id_cliente INT NOT NULL, 
	fecha_venta TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	estado VARCHAR(30) NOT NULL DEFAULT 'Pendiente de Pago' CHECK (estado IN ('Pendiente de Pago', 'Procesando', 'Enviado', 'Entregado', 'Cancelado')),
	total DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (total >= 0),
	FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

CREATE TABLE IF NOT EXISTS detalles_ventas (
	id_detalle INT AUTO_INCREMENT PRIMARY KEY,
	id_venta INT NOT NULL, 
	id_producto INT NOT NULL,
	cantidad INT NOT NULL CHECK (cantidad > 0),
	precio_unitario_congelado DECIMAL(10, 2) NOT NULL CHECK (precio_unitario_congelado > 0),
	
	FOREIGN KEY (id_venta) REFERENCES ventas(id_venta) ON DELETE CASCADE,
	FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);


SELECT * FROM clientes AS c; 



