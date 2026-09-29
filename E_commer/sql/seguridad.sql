-- =====================================================
-- 04_Seguridad.sql
-- Roles, usuarios, permisos, vistas y auditoría
-- =====================================================
USE E_commerce;

-- Tabla de log de cambios de precio (usada por Auditor_Financiero y por el trigger de auditoría)
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo DECIMAL(10,2) NOT NULL,
    usuario VARCHAR(100) NOT NULL DEFAULT 'desconocido',
    fecha_cambio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
);

-- Stub inicial; el script 07 lo reemplaza por la versión con parámetros y vuelve a otorgar EXECUTE
DELIMITER //
CREATE PROCEDURE IF NOT EXISTS sp_GenerarReporteMensualVentas()
BEGIN
    SELECT YEAR(fecha_venta) AS anio, MONTH(fecha_venta) AS mes, SUM(total) AS total_vendido
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY YEAR(fecha_venta), MONTH(fecha_venta);
END //
DELIMITER ;

-- ---------------- ROLES ----------------
CREATE ROLE IF NOT EXISTS 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON E_commerce.* TO 'Administrador_Sistema';

-- Columnas de clientes visibles para roles no administrativos (excluye contrasena)
CREATE ROLE IF NOT EXISTS 'Gerente_Marketing';
GRANT SELECT ON E_commerce.ventas TO 'Gerente_Marketing';
GRANT SELECT (id_cliente, nombre, apellido, email, direccion_envio, ciudad, fecha_nacimiento,
              fecha_registro, total_gastado, fecha_ultima_compra, activo)
      ON E_commerce.clientes TO 'Gerente_Marketing';

CREATE ROLE IF NOT EXISTS 'Analista_Datos';
GRANT SELECT ON E_commerce.productos TO 'Analista_Datos';
GRANT SELECT ON E_commerce.categorias TO 'Analista_Datos';
GRANT SELECT ON E_commerce.proveedores TO 'Analista_Datos';
GRANT SELECT ON E_commerce.ventas TO 'Analista_Datos';
GRANT SELECT ON E_commerce.detalles_ventas TO 'Analista_Datos';
GRANT SELECT (id_cliente, nombre, apellido, email, direccion_envio, ciudad, fecha_nacimiento,
              fecha_registro, total_gastado, fecha_ultima_compra, activo)
      ON E_commerce.clientes TO 'Analista_Datos';

CREATE ROLE IF NOT EXISTS 'Empleado_Inventario';
GRANT SELECT ON E_commerce.productos TO 'Empleado_Inventario';
GRANT UPDATE (stock) ON E_commerce.productos TO 'Empleado_Inventario';

CREATE ROLE IF NOT EXISTS 'Atencion_Cliente';
GRANT SELECT ON E_commerce.ventas TO 'Atencion_Cliente';
GRANT SELECT ON E_commerce.detalles_ventas TO 'Atencion_Cliente';
GRANT SELECT (id_cliente, nombre, apellido, email, direccion_envio, ciudad, fecha_registro, activo)
      ON E_commerce.clientes TO 'Atencion_Cliente';

CREATE ROLE IF NOT EXISTS 'Auditor_Financiero';
GRANT SELECT ON E_commerce.ventas TO 'Auditor_Financiero';
GRANT SELECT ON E_commerce.productos TO 'Auditor_Financiero';
GRANT SELECT ON E_commerce.log_cambios_precio TO 'Auditor_Financiero';

CREATE ROLE IF NOT EXISTS 'Visitante';
GRANT SELECT ON E_commerce.productos TO 'Visitante';

-- ---------------- USUARIOS ----------------
CREATE USER IF NOT EXISTS 'admin_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE ALL TO 'admin_user'@'localhost';

CREATE USER IF NOT EXISTS 'marketing_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
SET DEFAULT ROLE ALL TO 'marketing_user'@'localhost';

CREATE USER IF NOT EXISTS 'inventory_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
SET DEFAULT ROLE ALL TO 'inventory_user'@'localhost';

CREATE USER IF NOT EXISTS 'support_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';
SET DEFAULT ROLE ALL TO 'support_user'@'localhost';

CREATE USER IF NOT EXISTS 'analista_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!'
WITH MAX_QUERIES_PER_HOUR 1000;
GRANT 'Analista_Datos' TO 'analista_user'@'localhost';
SET DEFAULT ROLE ALL TO 'analista_user'@'localhost';

-- ---------------- PERMISOS ESPECÍFICOS Y VISTAS ----------------
GRANT EXECUTE ON PROCEDURE E_commerce.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';

CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT id_cliente, nombre, apellido, direccion_envio, fecha_registro
FROM clientes;
GRANT SELECT ON E_commerce.v_info_clientes_basica TO 'Atencion_Cliente';

CREATE OR REPLACE VIEW v_ventas_sucursal_1 AS
SELECT * FROM ventas WHERE id_sucursal = 1;

-- ---------------- POLÍTICAS DE SERVIDOR Y AUDITORÍA ----------------
-- Opcional (requiere el componente validate_password):
-- INSTALL COMPONENT 'file://component_validate_password';
-- SET GLOBAL validate_password.policy = 'MEDIUM';
-- SET GLOBAL validate_password.length = 8;

-- Elimina el acceso remoto de root
DROP USER IF EXISTS 'root'@'%';

CREATE TABLE IF NOT EXISTS log_intentos_login (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario VARCHAR(100),
    fecha_intento DATETIME DEFAULT CURRENT_TIMESTAMP,
    exitoso BOOLEAN,
    ip_origen VARCHAR(45)
);

FLUSH PRIVILEGES;