-- =====================================================
-- 06_Eventos.sql
-- Tablas de reportes y 20 eventos programados
-- =====================================================
USE E_commerce;

CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    semana_inicio DATE,
    semana_fin DATE,
    total_ventas DECIMAL(12,2),
    numero_ordenes INT
);
CREATE TABLE IF NOT EXISTS lista_reabastecimiento (
    id_item INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    stock_actual INT,
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS ventas_resumen_diario (
    fecha DATE PRIMARY KEY,
    total_ventas DECIMAL(12,2),
    numero_ordenes INT
);
-- NOTA: si ya habías ejecutado una versión anterior de este script, borra antes estas dos tablas de
-- reportes (DROP TABLE kpis_mensuales, reporte_proveedores_mensual) para que se creen con la clave UNIQUE.
CREATE TABLE IF NOT EXISTS kpis_mensuales (
    id_kpi INT AUTO_INCREMENT PRIMARY KEY,
    anio INT NOT NULL,
    mes INT NOT NULL,
    total_ventas DECIMAL(12,2),
    nuevos_clientes INT,
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_kpi_anio_mes (anio, mes)
);
CREATE TABLE IF NOT EXISTS log_tamano_bd (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    tamano_mb DECIMAL(10,2)
);
CREATE TABLE IF NOT EXISTS reporte_proveedores_mensual (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor INT NOT NULL,
    anio INT NOT NULL,
    mes INT NOT NULL,
    ingresos_generados DECIMAL(12,2),
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_prov_anio_mes (id_proveedor, anio, mes)
);
CREATE TABLE IF NOT EXISTS promociones (
    id_promocion INT AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(30) NOT NULL UNIQUE,
    porcentaje DECIMAL(5,2) NOT NULL,
    fecha_fin DATETIME NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS clientes_lealtad (
    id_cliente INT PRIMARY KEY,
    nivel VARCHAR(20),
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS inconsistencias_detectadas (
    id_inconsistencia INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT,
    descripcion VARCHAR(255),
    fecha_deteccion DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS saludos_cumpleanos (
    id_cliente INT,
    fecha DATE,
    PRIMARY KEY (id_cliente, fecha)
);
CREATE TABLE IF NOT EXISTS ranking_productos (
    id_producto INT PRIMARY KEY,
    unidades_vendidas INT,
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS carritos (
    id_carrito INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    fecha_actualizacion DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS mv_ventas_por_categoria (
    id_categoria INT PRIMARY KEY,
    nombre VARCHAR(100),
    unidades INT,
    ingresos DECIMAL(14,2),
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS alertas_fraude (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    pedidos_cancelados INT,
    fecha_alerta DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS log_cambios_precio_historico LIKE log_cambios_precio;
CREATE TABLE IF NOT EXISTS respaldo_ventas LIKE ventas;
CREATE TABLE IF NOT EXISTS respaldo_detalles_ventas LIKE detalles_ventas;

-- Activa el planificador ahora y lo deja persistente tras reiniciar el servidor
SET GLOBAL event_scheduler = ON;
SET PERSIST event_scheduler = ON;

DELIMITER $$

-- 1. Reporte de ventas semanal
CREATE EVENT IF NOT EXISTS evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, total_ventas, numero_ordenes)
    SELECT DATE_SUB(CURDATE(), INTERVAL 7 DAY), CURDATE(), COALESCE(SUM(total), 0), COUNT(*)
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND fecha_venta < CURDATE()
      AND estado <> 'Cancelado';
END$$

-- 2. Limpia alertas de stock con más de 30 días
CREATE EVENT IF NOT EXISTS evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM alertas_stock WHERE fecha_alerta < DATE_SUB(NOW(), INTERVAL 30 DAY);
END$$

-- 3. Archiva logs de precio de más de 6 meses en la tabla histórica
CREATE EVENT IF NOT EXISTS evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO log_cambios_precio_historico
    SELECT * FROM log_cambios_precio WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
    DELETE FROM log_cambios_precio WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END$$

-- 4. Desactiva promociones expiradas
CREATE EVENT IF NOT EXISTS evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE promociones SET activa = FALSE WHERE activa = TRUE AND fecha_fin < NOW();
END$$

-- 5. Recalcula el nivel de lealtad de los clientes cada noche
CREATE EVENT IF NOT EXISTS evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO
BEGIN
    INSERT INTO clientes_lealtad (id_cliente, nivel)
    SELECT n.id_cliente, n.nivel
    FROM (SELECT id_cliente, fn_DeterminarEstadoLealtad(id_cliente) AS nivel FROM clientes) AS n
    ON DUPLICATE KEY UPDATE nivel = n.nivel, fecha_calculo = NOW();
END$$

-- 6. Lista de productos por reabastecer
CREATE EVENT IF NOT EXISTS evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO lista_reabastecimiento (id_producto, stock_actual)
    SELECT p.id_producto, p.stock
    FROM productos p
    WHERE p.stock < p.stock_minimo AND p.activo = TRUE
      AND NOT EXISTS (SELECT 1 FROM lista_reabastecimiento l
                      WHERE l.id_producto = p.id_producto AND DATE(l.fecha_generacion) = CURDATE());
END$$

-- 7. Reconstruye tablas principales
CREATE EVENT IF NOT EXISTS evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
BEGIN
    OPTIMIZE TABLE productos, ventas, detalles_ventas;
END$$

-- 8. Mantenimiento de cuentas inactivas (política de retención: 2 años sin compras)
-- Reemplaza al evento anterior evt_suspend_inactive_accounts_quarterly (trimestral, 1 año),
-- que contradecía la política y desactivaba cuentas antes de tiempo.
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly$$
DROP EVENT IF EXISTS evt_desactivar_cuentas_inactivas$$
CREATE EVENT evt_desactivar_cuentas_inactivas
ON SCHEDULE EVERY 1 MONTH
STARTS (TIMESTAMP(DATE_FORMAT(CURDATE() + INTERVAL 1 MONTH, '%Y-%m-01')) + INTERVAL 3 HOUR)
COMMENT 'Desactiva clientes sin compras en los ultimos 2 anios (corre el dia 1 de cada mes, 03:00)'
DO
BEGIN
    -- Si el cliente nunca compro (fecha_ultima_compra NULL) se usa su fecha de registro
    UPDATE clientes
    SET activo = FALSE
    WHERE activo = TRUE
      AND COALESCE(fecha_ultima_compra, fecha_registro) < DATE_SUB(NOW(), INTERVAL 2 YEAR);
END$$

-- 9. Resumen diario de ventas: resume el día ANTERIOR completo, de madrugada
CREATE EVENT IF NOT EXISTS evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 5 MINUTE)
DO
BEGIN
    INSERT INTO ventas_resumen_diario (fecha, total_ventas, numero_ordenes)
    SELECT n.fecha, n.total_ventas, n.numero_ordenes
    FROM (SELECT DATE_SUB(CURDATE(), INTERVAL 1 DAY) AS fecha,
                 COALESCE(SUM(total), 0) AS total_ventas,
                 COUNT(*) AS numero_ordenes
          FROM ventas
          WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 1 DAY) AND fecha_venta < CURDATE()
            AND estado <> 'Cancelado') AS n
    ON DUPLICATE KEY UPDATE total_ventas = n.total_ventas, numero_ordenes = n.numero_ordenes;
END$$

-- 10. Detecta ventas sin detalles
CREATE EVENT IF NOT EXISTS evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO inconsistencias_detectadas (id_venta, descripcion)
    SELECT v.id_venta, 'Venta sin detalles'
    FROM ventas v
    WHERE NOT EXISTS (SELECT 1 FROM detalles_ventas dv WHERE dv.id_venta = v.id_venta)
      AND NOT EXISTS (SELECT 1 FROM inconsistencias_detectadas i
                      WHERE i.id_venta = v.id_venta AND i.descripcion = 'Venta sin detalles');
END$$

-- 11. Clientes que cumplen años hoy
CREATE EVENT IF NOT EXISTS evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT IGNORE INTO saludos_cumpleanos (id_cliente, fecha)
    SELECT id_cliente, CURDATE() FROM clientes
    WHERE activo = TRUE
      AND MONTH(fecha_nacimiento) = MONTH(CURDATE()) AND DAY(fecha_nacimiento) = DAY(CURDATE());
END$$

-- 12. Ranking de productos más vendidos
CREATE EVENT IF NOT EXISTS evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP
DO
BEGIN
    REPLACE INTO ranking_productos (id_producto, unidades_vendidas, fecha_calculo)
    SELECT p.id_producto, COALESCE(SUM(x.cantidad), 0), NOW()
    FROM productos p
    LEFT JOIN (SELECT dv.id_producto, dv.cantidad
               FROM detalles_ventas dv JOIN ventas v ON v.id_venta = dv.id_venta
               WHERE v.estado <> 'Cancelado') x ON x.id_producto = p.id_producto
    GROUP BY p.id_producto;
END$$

-- 13. Respaldo lógico nocturno de ventas y detalles (mysqldump sigue siendo el respaldo completo)
CREATE EVENT IF NOT EXISTS evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
BEGIN
    REPLACE INTO respaldo_ventas SELECT * FROM ventas;
    REPLACE INTO respaldo_detalles_ventas SELECT * FROM detalles_ventas;
END$$

-- 14. Vacía carritos abandonados (más de 72 horas)
CREATE EVENT IF NOT EXISTS evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM carritos WHERE fecha_actualizacion < DATE_SUB(NOW(), INTERVAL 72 HOUR);
END$$

-- 15. KPIs del mes anterior (corre el día 1 de cada mes; no duplica por la clave UNIQUE anio+mes)
CREATE EVENT IF NOT EXISTS evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH
STARTS (TIMESTAMP(DATE_FORMAT(CURDATE() + INTERVAL 1 MONTH, '%Y-%m-01')) + INTERVAL 1 HOUR)
DO
BEGIN
    DECLARE v_ini DATE DEFAULT DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01');
    DECLARE v_fin DATE DEFAULT DATE_FORMAT(CURDATE(), '%Y-%m-01');

    INSERT INTO kpis_mensuales (anio, mes, total_ventas, nuevos_clientes)
    SELECT n.anio, n.mes, n.total_ventas, n.nuevos_clientes
    FROM (SELECT YEAR(v_ini) AS anio, MONTH(v_ini) AS mes,
                 (SELECT COALESCE(SUM(total), 0) FROM ventas
                   WHERE estado <> 'Cancelado' AND fecha_venta >= v_ini AND fecha_venta < v_fin) AS total_ventas,
                 (SELECT COUNT(*) FROM clientes
                   WHERE fecha_registro >= v_ini AND fecha_registro < v_fin) AS nuevos_clientes) AS n
    ON DUPLICATE KEY UPDATE total_ventas = n.total_ventas,
                            nuevos_clientes = n.nuevos_clientes,
                            fecha_calculo = NOW();
END$$

-- 16. Refresca la "vista materializada" de ventas por categoría
CREATE EVENT IF NOT EXISTS evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM mv_ventas_por_categoria;
    INSERT INTO mv_ventas_por_categoria (id_categoria, nombre, unidades, ingresos)
    SELECT c.id_categoria, c.nombre,
           COALESCE(SUM(x.cantidad), 0),
           COALESCE(SUM(x.cantidad * x.precio_unitario_congelado), 0)
    FROM categorias c
    LEFT JOIN productos p ON p.id_categoria = c.id_categoria
    LEFT JOIN (SELECT dv.id_producto, dv.cantidad, dv.precio_unitario_congelado
               FROM detalles_ventas dv JOIN ventas v ON v.id_venta = dv.id_venta
               WHERE v.estado <> 'Cancelado') x ON x.id_producto = p.id_producto
    GROUP BY c.id_categoria, c.nombre;
END$$

-- 17. Tamaño de la base de datos
CREATE EVENT IF NOT EXISTS evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO log_tamano_bd (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables
    WHERE table_schema = DATABASE();
END$$

-- 18. Actividad sospechosa: 3 o más cancelaciones en la última hora (usa la fecha real de cancelación)
CREATE EVENT IF NOT EXISTS evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO alertas_fraude (id_cliente, pedidos_cancelados)
    SELECT v.id_cliente, COUNT(*)
    FROM log_cambio_estado_pedido l
    JOIN ventas v ON v.id_venta = l.id_venta
    WHERE l.estado_nuevo = 'Cancelado' AND l.fecha_cambio >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
    GROUP BY v.id_cliente
    HAVING COUNT(*) >= 3;
END$$

-- 19. Rendimiento mensual de proveedores (mes anterior completo; no duplica por UNIQUE proveedor+anio+mes)
CREATE EVENT IF NOT EXISTS evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS (TIMESTAMP(DATE_FORMAT(CURDATE() + INTERVAL 1 MONTH, '%Y-%m-01')) + INTERVAL 90 MINUTE)
DO
BEGIN
    DECLARE v_ini DATE DEFAULT DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01');
    DECLARE v_fin DATE DEFAULT DATE_FORMAT(CURDATE(), '%Y-%m-01');

    INSERT INTO reporte_proveedores_mensual (id_proveedor, anio, mes, ingresos_generados)
    SELECT n.id_proveedor, n.anio, n.mes, n.ingresos
    FROM (SELECT pr.id_proveedor, YEAR(v_ini) AS anio, MONTH(v_ini) AS mes,
                 SUM(dv.cantidad * dv.precio_unitario_congelado) AS ingresos
          FROM proveedores pr
          JOIN productos p ON p.id_proveedor = pr.id_proveedor
          JOIN detalles_ventas dv ON dv.id_producto = p.id_producto
          JOIN ventas v ON v.id_venta = dv.id_venta
          WHERE v.fecha_venta >= v_ini AND v.fecha_venta < v_fin AND v.estado <> 'Cancelado'
          GROUP BY pr.id_proveedor) AS n
    ON DUPLICATE KEY UPDATE ingresos_generados = n.ingresos, fecha_generacion = NOW();
END$$

-- 20. Purga productos con borrado lógico de más de 30 días (sin ventas asociadas)
CREATE EVENT IF NOT EXISTS evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM productos
    WHERE fecha_eliminacion IS NOT NULL
      AND fecha_eliminacion < DATE_SUB(NOW(), INTERVAL 30 DAY)
      AND NOT EXISTS (SELECT 1 FROM detalles_ventas d WHERE d.id_producto = productos.id_producto);
END$$

DELIMITER ;