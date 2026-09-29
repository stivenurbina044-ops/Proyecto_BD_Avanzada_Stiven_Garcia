-- =====================================================
-- 04_Seguridad.sql
-- Roles, usuarios, permisos y políticas de seguridad
-- =====================================================
USE E_commerce;

-- -----------------------------------------------------
-- PRE-REQUISITO: Tablas y Objetos Adicionales de Soporte
-- -----------------------------------------------------

-- Tabla para log de cambios de precios (requerida por Auditor_Financiero)
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo DECIMAL(10,2) NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    fecha_cambio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
    ON DELETE CASCADE
);

-- Stub para el procedimiento almacenado (requerido por Gerente_Marketing)
DELIMITER //
CREATE PROCEDURE IF NOT EXISTS sp_GenerarReporteMensualVentas()
BEGIN
    SELECT YEAR(fecha_venta) AS anio, MONTH(fecha_venta) AS mes, SUM(total) AS total_vendido
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY YEAR(fecha_venta), MONTH(fecha_venta);
END //
DELIMITER ;


-- -----------------------------------------------------
-- DEFINICIÓN DE ROLES Y ASIGNACIÓN DE PRIVILEGIOS
-- -----------------------------------------------------

-- 1. Rol Administrador_Sistema con todos los privilegios
CREATE ROLE IF NOT EXISTS 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON E_commerce.* TO 'Administrador_Sistema';

-- 2. Rol Gerente_Marketing con acceso de solo lectura a ventas y clientes
CREATE ROLE IF NOT EXISTS 'Gerente_Marketing';
GRANT SELECT ON E_commerce.ventas TO 'Gerente_Marketing';
GRANT SELECT ON E_commerce.clientes TO 'Gerente_Marketing';

-- 3. Rol Analista_Datos con acceso de solo lectura a todas las tablas principales
CREATE ROLE IF NOT EXISTS 'Analista_Datos';
GRANT SELECT ON E_commerce.productos TO 'Analista_Datos';
GRANT SELECT ON E_commerce.categorias TO 'Analista_Datos';
GRANT SELECT ON E_commerce.proveedores TO 'Analista_Datos';
GRANT SELECT ON E_commerce.clientes TO 'Analista_Datos';
GRANT SELECT ON E_commerce.ventas TO 'Analista_Datos';
GRANT SELECT ON E_commerce.detalles_ventas TO 'Analista_Datos';

-- 4. Rol Empleado_Inventario (Lectura general y modificación granular de stock)
CREATE ROLE IF NOT EXISTS 'Empleado_Inventario';
GRANT SELECT ON E_commerce.productos TO 'Empleado_Inventario';
GRANT UPDATE (stock) ON E_commerce.productos TO 'Empleado_Inventario';

-- 5. Rol Atencion_Cliente que puede ver clientes y ventas
CREATE ROLE IF NOT EXISTS 'Atencion_Cliente';
GRANT SELECT ON E_commerce.clientes TO 'Atencion_Cliente';
GRANT SELECT ON E_commerce.ventas TO 'Atencion_Cliente';
GRANT SELECT ON E_commerce.detalles_ventas TO 'Atencion_Cliente';

-- 6. Rol Auditor_Financiero con acceso de solo lectura a ventas, productos y logs de precios
CREATE ROLE IF NOT EXISTS 'Auditor_Financiero';
GRANT SELECT ON E_commerce.ventas TO 'Auditor_Financiero';
GRANT SELECT ON E_commerce.productos TO 'Auditor_Financiero';
GRANT SELECT ON E_commerce.log_cambios_precio TO 'Auditor_Financiero';

-- 17. Rol Visitante que solo puede ver la tabla productos
CREATE ROLE IF NOT EXISTS 'Visitante';
GRANT SELECT ON E_commerce.productos TO 'Visitante';


-- -----------------------------------------------------
-- CREACIÓN DE USUARIOS Y ASIGNACIÓN DE ROLES
-- -----------------------------------------------------

-- 7. Usuario admin_user
CREATE USER IF NOT EXISTS 'admin_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE ALL TO 'admin_user'@'localhost';

-- 8. Usuario marketing_user
CREATE USER IF NOT EXISTS 'marketing_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
SET DEFAULT ROLE ALL TO 'marketing_user'@'localhost';

-- 9. Usuario inventory_user
CREATE USER IF NOT EXISTS 'inventory_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
SET DEFAULT ROLE ALL TO 'inventory_user'@'localhost';

-- 10. Usuario support_user
CREATE USER IF NOT EXISTS 'support_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!';
GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';
SET DEFAULT ROLE ALL TO 'support_user'@'localhost';

-- 18. Usuario analista_user con límite de consultas por hora
CREATE USER IF NOT EXISTS 'analista_user'@'localhost' IDENTIFIED BY 'CambiarEstaClave123!'
WITH MAX_QUERIES_PER_HOUR 1000;
GRANT 'Analista_Datos' TO 'analista_user'@'localhost';
SET DEFAULT ROLE ALL TO 'analista_user'@'localhost';


-- -----------------------------------------------------
-- PERMISOS ESPECÍFICOS Y VISTAS DE SEGURIDAD
-- -----------------------------------------------------

-- 12. Otorgar a Gerente_Marketing permiso para ejecutar procedimiento de reportes
GRANT EXECUTE ON PROCEDURE E_commerce.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';

-- 13. Vista v_info_clientes_basica (Adaptada a la columna direccion_envio)
CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT id_cliente, nombre, apellido, direccion_envio, fecha_registro
FROM clientes;

GRANT SELECT ON E_commerce.v_info_clientes_basica TO 'Atencion_Cliente';

-- 19. Restringir ventas visibles por sucursal
ALTER TABLE ventas ADD COLUMN id_sucursal INT DEFAULT 1;

CREATE OR REPLACE VIEW v_ventas_sucursal_1 AS
SELECT * FROM ventas WHERE id_sucursal = 1;


-- -----------------------------------------------------
-- CONFIGURACIÓN DE POLÍTICAS DE SERVIDOR Y AUDITORÍA
-- -----------------------------------------------------

-- 15. Política de contraseñas seguras
-- NOTA: Requiere que el componente validate_password esté activo en MySQL.
-- Si da error en tu entorno local, instala el componente con: INSTALL COMPONENT 'file://component_validate_password';
SET GLOBAL validate_password.policy = 'MEDIUM';
SET GLOBAL validate_password.length = 8;

-- 16. Asegurar que el usuario root no pueda usarse desde conexiones remotas
DELETE FROM mysql.user WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- 20. Tabla para auditar intentos de inicio de sesión fallidos
CREATE TABLE IF NOT EXISTS log_intentos_login (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario VARCHAR(100),
    fecha_intento DATETIME DEFAULT CURRENT_TIMESTAMP,
    exitoso BOOLEAN,
    ip_origen VARCHAR(45)
);

FLUSH PRIVILEGES;