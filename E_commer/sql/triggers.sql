-- =====================================================
-- 05_Triggers.sql
-- Tablas de apoyo y triggers de validación y auditoría
-- =====================================================
USE E_commerce;

-- log_cambios_precio ya fue creada en 04_Seguridad.sql
CREATE TABLE IF NOT EXISTS log_nuevos_clientes (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_cambio_estado_pedido (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT,
    estado_anterior VARCHAR(30),
    estado_nuevo VARCHAR(30),
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertas_stock (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    stock_actual INT,
    fecha_alerta DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ventas_archivadas (
    id_venta INT,
    id_cliente INT,
    fecha_venta DATETIME,
    estado VARCHAR(30),
    total DECIMAL(12,2),
    fecha_archivado DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS log_permisos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    descripcion VARCHAR(255),
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- El contador de productos por categoría pasa a ser una VISTA: se calcula siempre desde
-- la fuente de verdad y no puede desincronizarse (la tabla + trigger anteriores solo cubrían INSERT).
DROP TABLE IF EXISTS contador_productos_categoria;
CREATE OR REPLACE VIEW v_productos_por_categoria AS
SELECT id_categoria, COUNT(*) AS total_productos
FROM productos
WHERE id_categoria IS NOT NULL
GROUP BY id_categoria;

DELIMITER $$

-- 1. Log de cambios de precio
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update$$
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo, usuario)
        VALUES (OLD.id_producto, OLD.precio, NEW.precio, LEFT(USER(), 100));  -- USER() = quien se conectó (CURRENT_USER() sería el definer)
    END IF;
END$$

-- 2. Verifica el stock antes de registrar un detalle de venta
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta$$
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalles_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = NEW.id_producto;
    IF v_stock < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta';
    END IF;
END$$

-- 3. Descuenta el stock después de insertar el detalle
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta$$
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalles_ventas
FOR EACH ROW
BEGIN
    UPDATE productos SET stock = stock - NEW.cantidad WHERE id_producto = NEW.id_producto;
END$$

-- 4. Impide eliminar una categoría con productos
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products$$
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count FROM productos WHERE id_categoria = OLD.id_categoria;
    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede eliminar una categoria con productos asociados';
    END IF;
END$$

-- 5. Registra cada nuevo cliente
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert$$
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_nuevos_clientes (id_cliente) VALUES (NEW.id_cliente);
END$$

-- 6a. Suma al total_gastado al insertar una venta
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente$$
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> 'Cancelado' THEN
        UPDATE clientes
        SET total_gastado = total_gastado + NEW.total,
            fecha_ultima_compra = NEW.fecha_venta
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$

-- 6b. Ajusta total_gastado si cambia el total o el estado (cancelaciones) de una venta
DROP TRIGGER IF EXISTS trg_update_total_gastado_on_venta_update$$
CREATE TRIGGER trg_update_total_gastado_on_venta_update
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    DECLARE v_delta DECIMAL(12,2) DEFAULT 0;
    IF OLD.id_cliente = NEW.id_cliente THEN
        IF OLD.estado <> 'Cancelado' THEN SET v_delta = v_delta - OLD.total; END IF;
        IF NEW.estado <> 'Cancelado' THEN SET v_delta = v_delta + NEW.total; END IF;
        IF v_delta <> 0 THEN
            UPDATE clientes SET total_gastado = total_gastado + v_delta WHERE id_cliente = NEW.id_cliente;
        END IF;
    END IF;
END$$

-- 7, 8 y 12. Validaciones de productos (stock, precio) y fecha de modificación
DROP TRIGGER IF EXISTS trg_productos_before_update$$
CREATE TRIGGER trg_productos_before_update
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El stock no puede ser negativo';
    END IF;
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El precio debe ser mayor que cero';
    END IF;
    SET NEW.fecha_modificacion = NOW();
END$$

-- 9. Capitaliza nombre y apellido
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente$$
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre, 1)), LOWER(SUBSTRING(NEW.nombre, 2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END$$

-- 10. Mantiene ventas.total y el stock cuando cambian los detalles (INSERT, UPDATE y DELETE)
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_change$$
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_after_insert_detalle$$
CREATE TRIGGER trg_recalculate_total_venta_after_insert_detalle
AFTER INSERT ON detalles_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
                 FROM detalles_ventas WHERE id_venta = NEW.id_venta)
    WHERE id_venta = NEW.id_venta;
END$$

DROP TRIGGER IF EXISTS trg_recalculate_total_venta_after_update_detalle$$
CREATE TRIGGER trg_recalculate_total_venta_after_update_detalle
AFTER UPDATE ON detalles_ventas
FOR EACH ROW
BEGIN
    DECLARE v_estado VARCHAR(30);
    -- Ajusta el stock si cambió la cantidad o el producto (salvo en ventas canceladas, cuyo stock ya se devolvió)
    IF OLD.cantidad <> NEW.cantidad OR OLD.id_producto <> NEW.id_producto THEN
        SELECT estado INTO v_estado FROM ventas WHERE id_venta = NEW.id_venta;
        IF v_estado <> 'Cancelado' THEN
            UPDATE productos SET stock = stock + OLD.cantidad WHERE id_producto = OLD.id_producto;
            UPDATE productos SET stock = stock - NEW.cantidad WHERE id_producto = NEW.id_producto;
        END IF;
    END IF;
    UPDATE ventas
    SET total = (SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
                 FROM detalles_ventas WHERE id_venta = NEW.id_venta)
    WHERE id_venta = NEW.id_venta;
END$$

DROP TRIGGER IF EXISTS trg_recalculate_total_venta_after_delete_detalle$$
CREATE TRIGGER trg_recalculate_total_venta_after_delete_detalle
AFTER DELETE ON detalles_ventas
FOR EACH ROW
BEGIN
    DECLARE v_estado VARCHAR(30);
    SELECT estado INTO v_estado FROM ventas WHERE id_venta = OLD.id_venta;
    IF v_estado IS NOT NULL AND v_estado <> 'Cancelado' THEN
        UPDATE productos SET stock = stock + OLD.cantidad WHERE id_producto = OLD.id_producto;
    END IF;
    UPDATE ventas
    SET total = (SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
                 FROM detalles_ventas WHERE id_venta = OLD.id_venta)
    WHERE id_venta = OLD.id_venta;
END$$

-- 11. Audita los cambios de estado de un pedido
DROP TRIGGER IF EXISTS trg_log_order_status_change$$
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO log_cambio_estado_pedido (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END$$

-- 13. Alerta de stock bajo
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock$$
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock <> OLD.stock AND NEW.stock < NEW.stock_minimo THEN
        INSERT INTO alertas_stock (id_producto, stock_actual) VALUES (NEW.id_producto, NEW.stock);
    END IF;
END$$

-- 14. Archiva las ventas eliminadas y devuelve el stock (el ON DELETE CASCADE de detalles_ventas NO dispara triggers)
DROP TRIGGER IF EXISTS trg_archive_deleted_venta$$
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total);

    IF OLD.estado <> 'Cancelado' THEN
        UPDATE productos p
        JOIN (SELECT id_producto, SUM(cantidad) AS c
              FROM detalles_ventas WHERE id_venta = OLD.id_venta
              GROUP BY id_producto) d ON d.id_producto = p.id_producto
        SET p.stock = p.stock + d.c;
        UPDATE clientes SET total_gastado = GREATEST(total_gastado - OLD.total, 0)
        WHERE id_cliente = OLD.id_cliente;
    END IF;
END$$

-- 15a. Valida el formato del email al insertar un cliente
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer$$
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Formato de correo electronico invalido';
    END IF;
END$$

-- 15b. Valida el formato del email al actualizar un cliente
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer_update$$
CREATE TRIGGER trg_validate_email_format_on_customer_update
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NEW.email <> OLD.email
       AND NEW.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Formato de correo electronico invalido';
    END IF;
END$$

-- 16. Mantiene clientes.fecha_ultima_compra coherente: es la fecha de la última compra NO cancelada.
--     (6a la fija al crear la venta; aquí se recalcula cuando una venta se cancela o se reactiva.
--      Ya no se sobrescribe con la fecha de entrega.)
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer$$
CREATE TRIGGER trg_update_last_order_date_customer
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado AND (OLD.estado = 'Cancelado' OR NEW.estado = 'Cancelado') THEN
        UPDATE clientes
        SET fecha_ultima_compra = (SELECT MAX(fecha_venta) FROM ventas
                                   WHERE id_cliente = NEW.id_cliente AND estado <> 'Cancelado')
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$

-- 17. Devuelve el stock al cancelar un pedido (y lo vuelve a descontar si se reactiva)
DROP TRIGGER IF EXISTS trg_restore_stock_on_cancel$$
CREATE TRIGGER trg_restore_stock_on_cancel
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Cancelado' AND OLD.estado <> 'Cancelado' THEN
        UPDATE productos p
        JOIN (SELECT id_producto, SUM(cantidad) AS c
              FROM detalles_ventas WHERE id_venta = NEW.id_venta
              GROUP BY id_producto) d ON d.id_producto = p.id_producto
        SET p.stock = p.stock + d.c;
    ELSEIF OLD.estado = 'Cancelado' AND NEW.estado <> 'Cancelado' THEN
        UPDATE productos p
        JOIN (SELECT id_producto, SUM(cantidad) AS c
              FROM detalles_ventas WHERE id_venta = NEW.id_venta
              GROUP BY id_producto) d ON d.id_producto = p.id_producto
        SET p.stock = p.stock - d.c;   -- si no alcanza, el CHECK (stock >= 0) rechaza la reactivación
    END IF;
END$$

-- 18. Audita cambios del estado activo de un producto
DROP TRIGGER IF EXISTS trg_log_permission_changes$$
CREATE TRIGGER trg_log_permission_changes
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.activo <> NEW.activo THEN
        INSERT INTO log_permisos (descripcion)
        VALUES (CONCAT('Cambio de estado activo en producto ID: ', NEW.id_producto));
    END IF;
END$$

-- 19. Asigna la categoría "General" si el producto se inserta sin categoría
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null$$
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SET NEW.id_categoria = (SELECT id_categoria FROM categorias WHERE nombre = 'General' LIMIT 1);
    END IF;
END$$

-- 20. (Eliminado) El contador de productos por categoría ahora es la vista v_productos_por_categoria.
DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria$$

DELIMITER ;