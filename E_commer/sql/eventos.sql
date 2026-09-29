-- =====================================================
-- 06_Eventos.sql
-- Tabla de reportes semanales y 20 eventos programados
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

-- Tablas auxiliares usadas por algunos eventos
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

CREATE TABLE IF NOT EXISTS kpis_mensuales (
    id_kpi INT AUTO_INCREMENT PRIMARY KEY,
    anio INT,
    mes INT,
    total_ventas DECIMAL(12,2),
    nuevos_clientes INT,
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_tamano_bd (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    tamano_mb DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS reporte_proveedores_mensual (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor INT,
    ingresos_generados DECIMAL(12,2),
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

SET GLOBAL event_scheduler = ON;

DELIMITER $$

-- 1. Genera un reporte de ventas semanal
CREATE EVENT IF NOT EXISTS EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, total_ventas, numero_ordenes)
    SELECT DATE_SUB(CURDATE(), INTERVAL 7 DAY), CURDATE(), SUM(total), COUNT(*)
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY);
END$$

-- 2. Borra tablas temporales diariamente (ejemplo generico)
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_calculo_diario;
END$$

-- 3. Archiva logs de mas de 6 meses en tablas historicas
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM log_cambios_precio WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END$$

-- 4. Desactiva codigos de descuento expirados (requiere tabla promociones)
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- UPDATE promociones SET activa = FALSE WHERE fecha_fin < NOW();
    SELECT 1;
END$$

-- 5. Recalcula el nivel de lealtad de los clientes cada noche
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO
BEGIN
    -- El nivel se calcula al vuelo con fn_DeterminarEstadoLealtad; aqui se deja como placeholder
    -- para una tabla clientes_lealtad si se decide materializar el resultado
    SELECT 1;
END$$

-- 6. Crea una lista de productos que necesitan ser reabastecidos
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO lista_reabastecimiento (id_producto, stock_actual)
    SELECT id_producto, stock FROM productos WHERE stock < stock_minimo AND activo = TRUE;
END$$

-- 7. Reconstruye indices de las tablas mas usadas
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    OPTIMIZE TABLE productos, ventas, detalle_ventas;
END$$

-- 8. Suspende cuentas de clientes sin actividad en mas de un ano
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Requiere columna 'activo' en clientes para marcar la cuenta como inactiva
    -- UPDATE clientes SET activo = FALSE WHERE fecha_ultima_compra < DATE_SUB(NOW(), INTERVAL 1 YEAR);
    SELECT 1;
END$$

-- 9. Agrega los datos de ventas del dia en una tabla de resumen
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO ventas_resumen_diario (fecha, total_ventas, numero_ordenes)
    SELECT CURDATE(), SUM(total), COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE()
    ON DUPLICATE KEY UPDATE total_ventas = VALUES(total_ventas), numero_ordenes = VALUES(numero_ordenes);
END$$

-- 10. Busca inconsistencias en los datos (ej. ventas sin detalles)
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Placeholder: se podria insertar en una tabla de inconsistencias_detectadas
    SELECT v.id_venta FROM ventas v
    LEFT JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    WHERE dv.id_detalle IS NULL;
END$$

-- 11. Genera lista de clientes que cumplen anos para enviarles un cupon
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    SELECT id_cliente, nombre, apellido, email
    FROM clientes
    WHERE MONTH(fecha_nacimiento) = MONTH(CURDATE()) AND DAY(fecha_nacimiento) = DAY(CURDATE());
END$$

-- 12. Actualiza una tabla con el ranking de productos mas populares
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Requiere tabla ranking_productos(id_producto, unidades_vendidas, fecha_calculo)
    SELECT 1;
END$$

-- 13. Realiza un backup logico de las tablas mas importantes cada noche
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
BEGIN
    -- El backup real se ejecuta con mysqldump desde el sistema operativo (cron), no desde SQL puro
    SELECT 1;
END$$

-- 14. Vacia los carritos de compra abandonados hace mas de 72 horas (requiere tabla carritos)
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- DELETE FROM carritos WHERE fecha_actualizacion < DATE_SUB(NOW(), INTERVAL 72 HOUR);
    SELECT 1;
END$$

-- 15. Calcula los KPIs del mes y los guarda en una tabla
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO kpis_mensuales (anio, mes, total_ventas, nuevos_clientes)
    SELECT YEAR(CURDATE()), MONTH(CURDATE()),
           (SELECT SUM(total) FROM ventas WHERE YEAR(fecha_venta)=YEAR(CURDATE()) AND MONTH(fecha_venta)=MONTH(CURDATE())),
           (SELECT COUNT(*) FROM clientes WHERE YEAR(fecha_registro)=YEAR(CURDATE()) AND MONTH(fecha_registro)=MONTH(CURDATE()));
END$$

-- 16. Actualiza las vistas materializadas (simuladas con tablas resumen)
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Se refresca la vista v_info_clientes_basica si aplicara materializacion
    SELECT 1;
END$$

-- 17. Registra el tamano de la base de datos para monitorear su crecimiento
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO log_tamano_bd (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables
    WHERE table_schema = 'ecommerce_db';
END$$

-- 18. Busca patrones de actividad sospechosa (ej. multiples pedidos fallidos)
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    SELECT id_cliente, COUNT(*) AS pedidos_cancelados
    FROM ventas
    WHERE estado = 'Cancelado' AND fecha_venta >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
    GROUP BY id_cliente
    HAVING pedidos_cancelados >= 3;
END$$

-- 19. Crea un reporte mensual sobre el rendimiento de los proveedores
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO reporte_proveedores_mensual (id_proveedor, ingresos_generados)
    SELECT pr.id_proveedor, SUM(dv.cantidad * dv.precio_unitario_congelado)
    FROM proveedores pr
    JOIN productos p ON p.id_proveedor = pr.id_proveedor
    JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    JOIN ventas v ON v.id_venta = dv.id_venta
    WHERE v.fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
    GROUP BY pr.id_proveedor;
END$$

-- 20. Elimina permanentemente registros marcados para borrado hace mas de 30 dias
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Requiere columna de borrado logico (ej. fecha_eliminacion) en las tablas relevantes
    -- DELETE FROM productos WHERE fecha_eliminacion < DATE_SUB(NOW(), INTERVAL 30 DAY);
    SELECT 1;
END$$

DELIMITER ;