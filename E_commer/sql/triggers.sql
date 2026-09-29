USE E_commerce;
-- ---------------------------------------------------
-- 1. ASEGURAR COLUMNAS NECESARIAS EN TABLAS
-- -----------------------------------------------------
DELIMITER //
CREATE PROCEDURE IF NOT EXISTS sp_preparar_tablas_triggers()
BEGIN
    -- Agregar fecha_modificacion a productos si no existe
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'E_commerce' AND TABLE_NAME = 'productos' AND COLUMN_NAME = 'fecha_modificacion') THEN
        ALTER TABLE productos ADD COLUMN fecha_modificacion DATETIME NULL;
    END IF;

    -- Agregar activo a productos
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'E_commerce' AND TABLE_NAME = 'productos' AND COLUMN_NAME = 'activo') THEN
        ALTER TABLE productos ADD COLUMN activo BOOLEAN DEFAULT TRUE;
    END IF;

    -- Agregar stock_minimo a productos
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'E_commerce' AND TABLE_NAME = 'productos' AND COLUMN_NAME = 'stock_minimo') THEN
        ALTER TABLE productos ADD COLUMN stock_minimo INT DEFAULT 5;
    END IF;

    -- Agregar total_gastado a clientes
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'E_commerce' AND TABLE_NAME = 'clientes' AND COLUMN_NAME = 'total_gastado') THEN
        ALTER TABLE clientes ADD COLUMN total_gastado DECIMAL(12,2) DEFAULT 0.00;
    END IF;

    -- Agregar fecha_ultima_compra a clientes
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'E_commerce' AND TABLE_NAME = 'clientes' AND COLUMN_NAME = 'fecha_ultima_compra') THEN
        ALTER TABLE clientes ADD COLUMN fecha_ultima_compra DATETIME NULL;
    END IF;
END //
DELIMITER ;

CALL sp_preparar_tablas_triggers();
DROP PROCEDURE IF EXISTS sp_preparar_tablas_triggers;

-- Tabla de auditoria de cambios de precio
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    precio_anterior DECIMAL(10,2),
    precio_nuevo DECIMAL(10,2),
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tablas auxiliares usadas por los triggers
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
DELIMITER $$

-- 1. Guarda un log de cambios de precios
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update$$
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo)
        VALUES (OLD.id_producto, OLD.precio, NEW.precio);
    END IF;
END$$

-- 2. Verifica el stock antes de registrar el detalle de una venta
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta$$
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalles_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = NEW.id_producto;
    IF v_stock < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta';
    END IF;
END$$

-- 3. Decrementa el stock despues de insertar el detalle de una venta
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta$$
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalles_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END$$

-- 4. Impide eliminar una categoria si tiene productos asociados
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products$$
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count FROM productos WHERE id_categoria = OLD.id_categoria;
    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar una categoria con productos asociados';
    END IF;
END$$

-- 5. Registra en auditoria cada nuevo cliente
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert$$
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_nuevos_clientes (id_cliente) VALUES (NEW.id_cliente);
END$$

-- 6. Actualiza total_gastado del cliente despues de cada venta
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente$$
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET total_gastado = total_gastado + NEW.total,
        fecha_ultima_compra = NEW.fecha_venta
    WHERE id_cliente = NEW.id_cliente;
END$$

-- 7, 8 y 12. Validaciones consolidadas en BEFORE UPDATE para productos
-- (Elimina el trigger antiguo separado para evitar duplicados)
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto$$
DROP TRIGGER IF EXISTS trg_prevent_negative_stock$$
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less$$
DROP TRIGGER IF EXISTS trg_productos_before_update$$
CREATE TRIGGER trg_productos_before_update
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El stock no puede ser negativo';
    END IF;

    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El precio debe ser mayor que cero';
    END IF;

    SET NEW.fecha_modificacion = NOW();
END$$

-- 9. Convierte a mayuscula la primera letra del nombre y apellido al insertar un cliente
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente$$
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre,1)), LOWER(SUBSTRING(NEW.nombre,2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido,1)), LOWER(SUBSTRING(NEW.apellido,2)));
END$$

-- 10. Recalcula el total de la venta si se modifica un detalles_venta
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_change$$
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER UPDATE ON detalles_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (SELECT COALESCE(SUM(cantidad * precio_unitario), 0) FROM detalles_ventas WHERE id_venta = NEW.id_venta)
    WHERE id_venta = NEW.id_venta;
END$$

-- 11. Audita cada cambio de estado de un pedido
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

-- 13. Inserta una alerta si el stock baja de un umbral
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock$$
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < NEW.stock_minimo THEN
        INSERT INTO alertas_stock (id_producto, stock_actual) VALUES (NEW.id_producto, NEW.stock);
    END IF;
END$$

-- 14. Mueve una venta eliminada a una tabla de archivo
DROP TRIGGER IF EXISTS trg_archive_deleted_venta$$
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total);
END$$

-- 15. Valida el formato del email antes de insertar o actualizar un cliente
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer$$
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Formato de correo electronico invalido';
    END IF;
END$$

-- 16. Actualiza la fecha del ultimo pedido en la tabla clientes
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer$$
CREATE TRIGGER trg_update_last_order_date_customer
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Entregado' AND OLD.estado <> 'Entregado' THEN
        UPDATE clientes SET fecha_ultima_compra = NOW() WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$

-- 17. Impide que un cliente se referencie a si mismo
DROP TRIGGER IF EXISTS trg_prevent_self_referral$$
CREATE TRIGGER trg_prevent_self_referral
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NEW.direccion_envio = 'REF_SELF' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un cliente no puede referenciarse a si mismo';
    END IF;
END$$

-- 18. Audita los cambios en los permisos/estado del producto
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

-- 19. Asigna la categoria "General" si se inserta un producto sin categoria
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null$$
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SET NEW.id_categoria = (SELECT id_categoria FROM categorias WHERE nombre = 'General' LIMIT 1);
    END IF;
END$$

-- 20. Mantiene un contador de productos por categoria
DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria$$
CREATE TRIGGER trg_update_producto_count_in_categoria
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    INSERT INTO contador_productos_categoria (id_categoria, total_productos)
    VALUES (NEW.id_categoria, 1)
    ON DUPLICATE KEY UPDATE total_productos = total_productos + 1;
END$$

DELIMITER ;

DELIMITER $$

DROP TRIGGER IF EXISTS trg_productos_before_update$$
CREATE TRIGGER trg_productos_before_update
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    -- Validar stock no negativo
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El stock no puede ser negativo';
    END IF;

    -- Validar precio mayor a cero
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El precio debe ser mayor que cero';
    END IF;
END$$

DELIMITER ;

