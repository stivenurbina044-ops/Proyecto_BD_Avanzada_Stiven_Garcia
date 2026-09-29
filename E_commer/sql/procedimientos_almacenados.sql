-- 07_Procedimientos_Almacenados.sql
USE E_commerce;

CREATE TABLE IF NOT EXISTS devoluciones (
    id_devolucion INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT,
    id_producto INT,
    cantidad INT,
    motivo VARCHAR(255),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS ajustes_inventario (
    id_ajuste INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    cantidad_ajustada INT,
    motivo VARCHAR(255),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS resenas_producto (
    id_resena INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    id_cliente INT,
    calificacion INT,
    comentario TEXT,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

-- 1. Nueva venta (transaccional)
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta$$
CREATE PROCEDURE sp_RealizarNuevaVenta(IN p_id_cliente INT, IN p_id_producto INT, IN p_cantidad INT)
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_id_venta INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT precio INTO v_precio FROM productos
    WHERE id_producto = p_id_producto AND activo = TRUE FOR UPDATE;

    IF v_precio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe o no esta activo';
    END IF;

    INSERT INTO ventas (id_cliente, estado, total) VALUES (p_id_cliente, 'Pendiente de Pago', 0);
    SET v_id_venta = LAST_INSERT_ID();

    INSERT INTO detalles_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
    VALUES (v_id_venta, p_id_producto, p_cantidad, v_precio);

    UPDATE ventas SET total = p_cantidad * v_precio WHERE id_venta = v_id_venta;

    COMMIT;
END$$

-- 2. Nuevo producto
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto$$
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(100), IN p_descripcion TEXT, IN p_precio DECIMAL(10,2), IN p_costo DECIMAL(10,2),
    IN p_stock INT, IN p_sku VARCHAR(50), IN p_id_categoria INT, IN p_id_proveedor INT)
BEGIN
    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor)
    VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock, p_sku, p_id_categoria, p_id_proveedor);
END$$

-- 3. Actualiza la dirección de un cliente
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente$$
CREATE PROCEDURE sp_ActualizarDireccionCliente(IN p_id_cliente INT, IN p_nueva_direccion VARCHAR(255))
BEGIN
    UPDATE clientes SET direccion_envio = p_nueva_direccion WHERE id_cliente = p_id_cliente;
END$$

-- 4. Devolución de un producto (valida cantidades)
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion$$
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta INT, IN p_id_producto INT, IN p_cantidad INT, IN p_motivo VARCHAR(255))
BEGIN
    DECLARE v_comprado INT;
    DECLARE v_devuelto INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COALESCE(SUM(cantidad), 0) INTO v_comprado FROM detalles_ventas
    WHERE id_venta = p_id_venta AND id_producto = p_id_producto;
    SELECT COALESCE(SUM(cantidad), 0) INTO v_devuelto FROM devoluciones
    WHERE id_venta = p_id_venta AND id_producto = p_id_producto;

    IF p_cantidad <= 0 OR p_cantidad > (v_comprado - v_devuelto) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cantidad de devolucion invalida para esta venta';
    END IF;

    START TRANSACTION;
    INSERT INTO devoluciones (id_venta, id_producto, cantidad, motivo)
    VALUES (p_id_venta, p_id_producto, p_cantidad, p_motivo);
    UPDATE productos SET stock = stock + p_cantidad WHERE id_producto = p_id_producto;
    COMMIT;
END$$

-- 5. Historial de compras de un cliente
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente$$
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT v.id_venta, v.fecha_venta, v.estado, v.total,
           p.nombre AS producto, dv.cantidad, dv.precio_unitario_congelado
    FROM ventas v
    JOIN detalles_ventas dv ON dv.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END$$

-- 6. Ajuste manual de stock
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock$$
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT, IN p_cantidad_ajustada INT, IN p_motivo VARCHAR(255))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    UPDATE productos SET stock = stock + p_cantidad_ajustada WHERE id_producto = p_id_producto;
    INSERT INTO ajustes_inventario (id_producto, cantidad_ajustada, motivo)
    VALUES (p_id_producto, p_cantidad_ajustada, p_motivo);
    COMMIT;
END$$

-- 7. Anonimiza un cliente
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura$$
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
    SET nombre = 'Anonimo', apellido = 'Anonimo',
        email = CONCAT('eliminado_', p_id_cliente, '@anonimo.com'),
        contrasena = 'N/A', direccion_envio = NULL, ciudad = NULL, fecha_nacimiento = NULL,
        activo = FALSE
    WHERE id_cliente = p_id_cliente;
END$$

-- 8. Descuento por categoría
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria$$
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(IN p_id_categoria INT, IN p_porcentaje DECIMAL(5,2))
BEGIN
    IF p_porcentaje <= 0 OR p_porcentaje >= 100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje debe estar entre 0 y 100 (exclusivo)';
    END IF;
    UPDATE productos SET precio = ROUND(precio - (precio * (p_porcentaje / 100)), 2)
    WHERE id_categoria = p_id_categoria;
END$$

-- 9. Reporte mensual de ventas (reemplaza el stub creado en 04_Seguridad.sql)
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas$$
CREATE PROCEDURE sp_GenerarReporteMensualVentas(IN p_anio INT, IN p_mes INT)
BEGIN
    SELECT v.id_venta, v.fecha_venta, c.nombre, c.apellido, v.total, v.estado
    FROM ventas v
    JOIN clientes c ON c.id_cliente = v.id_cliente
    WHERE YEAR(v.fecha_venta) = p_anio AND MONTH(v.fecha_venta) = p_mes
    ORDER BY v.fecha_venta;
END$$

-- 10. Cambia el estado de un pedido
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido$$
CREATE PROCEDURE sp_CambiarEstadoPedido(IN p_id_venta INT, IN p_nuevo_estado VARCHAR(30))
BEGIN
    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
END$$

-- 11. Registra un cliente validando que el email no exista
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente$$
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100), IN p_apellido VARCHAR(100), IN p_email VARCHAR(100),
    IN p_contrasena VARCHAR(255), IN p_direccion VARCHAR(255))
BEGIN
    DECLARE v_existe INT;
    SELECT COUNT(*) INTO v_existe FROM clientes WHERE email = p_email;
    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El correo electronico ya esta registrado';
    ELSE
        INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
        VALUES (p_nombre, p_apellido, p_email, p_contrasena, p_direccion);
    END IF;
END$$

-- 12. Detalle completo de un producto
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto$$
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT p.*, c.nombre AS categoria, pr.nombre AS proveedor, pr.email_contacto
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    LEFT JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$

-- 13. Fusiona dos cuentas de cliente
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente$$
CREATE PROCEDURE sp_FusionarCuentasCliente(IN p_id_cliente_principal INT, IN p_id_cliente_duplicado INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_id_cliente_principal = p_id_cliente_duplicado THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las cuentas a fusionar deben ser distintas';
    END IF;
    IF (SELECT COUNT(*) FROM clientes
        WHERE id_cliente IN (p_id_cliente_principal, p_id_cliente_duplicado)) < 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alguna de las cuentas no existe';
    END IF;

    START TRANSACTION;

    UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    UPDATE resenas_producto SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;

    UPDATE clientes c1
    JOIN clientes c2 ON c2.id_cliente = p_id_cliente_duplicado
    SET c1.total_gastado = c1.total_gastado + c2.total_gastado,
        c1.fecha_ultima_compra = NULLIF(
            GREATEST(COALESCE(c1.fecha_ultima_compra, '1000-01-01'),
                     COALESCE(c2.fecha_ultima_compra, '1000-01-01')), '1000-01-01')
    WHERE c1.id_cliente = p_id_cliente_principal;

    DELETE FROM clientes WHERE id_cliente = p_id_cliente_duplicado;

    COMMIT;
END$$

-- 14. Asigna proveedor a un producto
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor$$
CREATE PROCEDURE sp_AsignarProductoAProveedor(IN p_id_producto INT, IN p_id_proveedor INT)
BEGIN
    UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
END$$

-- 15. Búsqueda avanzada de productos
DROP PROCEDURE IF EXISTS sp_BuscarProductos$$
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(100), IN p_id_categoria INT, IN p_precio_min DECIMAL(10,2), IN p_precio_max DECIMAL(10,2))
BEGIN
    SELECT * FROM productos
    WHERE (p_nombre IS NULL OR nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR precio >= p_precio_min)
      AND (p_precio_max IS NULL OR precio <= p_precio_max)
      AND activo = TRUE;
END$$

-- 16. KPIs para el panel de administración
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin$$
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT COALESCE(SUM(total), 0) FROM ventas
          WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ventas_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE()) AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Pendiente de Pago') AS pedidos_pendientes,
        (SELECT COUNT(*) FROM productos WHERE stock < stock_minimo) AS productos_bajo_stock;
END$$

-- 17. Procesa el pago de una venta
DROP PROCEDURE IF EXISTS sp_ProcesarPago$$
CREATE PROCEDURE sp_ProcesarPago(IN p_id_venta INT)
BEGIN
    UPDATE ventas SET estado = 'Procesando'
    WHERE id_venta = p_id_venta AND estado = 'Pendiente de Pago';
END$$

-- 18. Reseña de un producto comprado
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto$$
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_producto INT, IN p_id_cliente INT, IN p_calificacion INT, IN p_comentario TEXT)
BEGIN
    DECLARE v_compro INT;
    IF p_calificacion NOT BETWEEN 1 AND 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La calificacion debe estar entre 1 y 5';
    END IF;

    SELECT COUNT(*) INTO v_compro
    FROM detalles_ventas dv
    JOIN ventas v ON v.id_venta = dv.id_venta
    WHERE v.id_cliente = p_id_cliente AND dv.id_producto = p_id_producto AND v.estado <> 'Cancelado';

    IF v_compro = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente no ha comprado este producto';
    ELSE
        INSERT INTO resenas_producto (id_producto, id_cliente, calificacion, comentario)
        VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
    END IF;
END$$

-- 19. Productos relacionados
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados$$
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT p.id_producto, p.nombre, COUNT(*) AS veces_comprado_junto
    FROM detalles_ventas dv1
    JOIN detalles_ventas dv2 ON dv1.id_venta = dv2.id_venta AND dv1.id_producto <> dv2.id_producto
    JOIN productos p ON p.id_producto = dv2.id_producto
    WHERE dv1.id_producto = p_id_producto
    GROUP BY p.id_producto, p.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END$$

-- 20. Mueve productos entre categorías
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias$$
CREATE PROCEDURE sp_MoverProductosEntreCategorias(IN p_id_categoria_origen INT, IN p_id_categoria_destino INT)
BEGIN
    DECLARE v_existe_destino INT;
    SELECT COUNT(*) INTO v_existe_destino FROM categorias WHERE id_categoria = p_id_categoria_destino;
    IF v_existe_destino = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La categoria destino no existe';
    ELSE
        UPDATE productos SET id_categoria = p_id_categoria_destino WHERE id_categoria = p_id_categoria_origen;
    END IF;
END$$

DELIMITER ;

-- Al reemplazar el stub de 04_Seguridad.sql se vuelve a otorgar el permiso
GRANT EXECUTE ON PROCEDURE E_commerce.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';