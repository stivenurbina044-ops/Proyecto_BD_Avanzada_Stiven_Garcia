-- =====================================================
-- 07_Procedimientos_Almacenados.sql
-- 20 procedimientos almacenados
-- =====================================================
USE E_commerce;

-- Tabla auxiliar para devoluciones y ajustes de stock
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

-- 1. Procesa una nueva venta de forma transaccional
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_producto INT,
    IN p_cantidad INT
)
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_id_venta INT;

    START TRANSACTION;

    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto FOR UPDATE;

    INSERT INTO ventas (id_cliente, estado, total) VALUES (p_id_cliente, 'Pendiente de Pago', 0);
    SET v_id_venta = LAST_INSERT_ID();

    INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
    VALUES (v_id_venta, p_id_producto, p_cantidad, v_precio);

    UPDATE ventas SET total = p_cantidad * v_precio WHERE id_venta = v_id_venta;

    COMMIT;
END$$

-- 2. Inserta un nuevo producto y sus atributos iniciales
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(150),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(10,2),
    IN p_costo DECIMAL(10,2),
    IN p_stock INT,
    IN p_sku VARCHAR(50),
    IN p_id_categoria INT,
    IN p_id_proveedor INT
)
BEGIN
    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor)
    VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock, p_sku, p_id_categoria, p_id_proveedor);
END$$

-- 3. Actualiza la direccion de un cliente
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion VARCHAR(255)
)
BEGIN
    UPDATE clientes SET direccion_envio = p_nueva_direccion WHERE id_cliente = p_id_cliente;
END$$

-- 4. Gestiona la devolucion de un producto, ajustando el stock y generando un registro
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta INT,
    IN p_id_producto INT,
    IN p_cantidad INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    START TRANSACTION;

    INSERT INTO devoluciones (id_venta, id_producto, cantidad, motivo)
    VALUES (p_id_venta, p_id_producto, p_cantidad, p_motivo);

    UPDATE productos SET stock = stock + p_cantidad WHERE id_producto = p_id_producto;

    COMMIT;
END$$

-- 5. Devuelve el historial completo de compras de un cliente
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT v.id_venta, v.fecha_venta, v.estado, v.total,
           p.nombre AS producto, dv.cantidad, dv.precio_unitario_congelado
    FROM ventas v
    JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END$$

-- 6. Permite ajustar manualmente el stock de un producto, registrando el motivo
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_cantidad_ajustada INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    START TRANSACTION;

    UPDATE productos SET stock = stock + p_cantidad_ajustada WHERE id_producto = p_id_producto;

    INSERT INTO ajustes_inventario (id_producto, cantidad_ajustada, motivo)
    VALUES (p_id_producto, p_cantidad_ajustada, p_motivo);

    COMMIT;
END$$

-- 7. Anonimiza los datos de un cliente en lugar de borrarlos
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
    SET nombre = 'Anonimo',
        apellido = 'Anonimo',
        email = CONCAT('eliminado_', p_id_cliente, '@anonimo.com'),
        contrasena = 'N/A',
        direccion_envio = NULL
    WHERE id_cliente = p_id_cliente;
END$$

-- 8. Aplica un descuento a todos los productos de una categoria especifica
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje DECIMAL(5,2)
)
BEGIN
    UPDATE productos
    SET precio = precio - (precio * (p_porcentaje / 100))
    WHERE id_categoria = p_id_categoria;
END$$

-- 9. Genera un reporte completo de ventas para un mes y ano dados
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_anio INT,
    IN p_mes INT
)
BEGIN
    SELECT v.id_venta, v.fecha_venta, c.nombre, c.apellido, v.total, v.estado
    FROM ventas v
    JOIN clientes c ON c.id_cliente = v.id_cliente
    WHERE YEAR(v.fecha_venta) = p_anio AND MONTH(v.fecha_venta) = p_mes
    ORDER BY v.fecha_venta;
END$$

-- 10. Cambia el estado de un pedido
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(30)
)
BEGIN
    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
END$$

-- 11. Registra un nuevo cliente validando que el email no exista
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100),
    IN p_apellido VARCHAR(100),
    IN p_email VARCHAR(150),
    IN p_contrasena VARCHAR(255),
    IN p_direccion VARCHAR(255)
)
BEGIN
    DECLARE v_existe INT;
    SELECT COUNT(*) INTO v_existe FROM clientes WHERE email = p_email;

    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El correo electronico ya esta registrado';
    ELSE
        INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
        VALUES (p_nombre, p_apellido, p_email, p_contrasena, p_direccion);
    END IF;
END$$

-- 12. Devuelve toda la informacion de un producto, incluyendo proveedor y categoria
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT p.*, c.nombre AS categoria, pr.nombre AS proveedor, pr.email_contacto
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    LEFT JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$

-- 13. Fusiona dos cuentas de cliente duplicadas en una sola
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_principal INT,
    IN p_id_cliente_duplicado INT
)
BEGIN
    START TRANSACTION;

    UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;

    UPDATE clientes c1
    JOIN clientes c2 ON c2.id_cliente = p_id_cliente_duplicado
    SET c1.total_gastado = c1.total_gastado + c2.total_gastado
    WHERE c1.id_cliente = p_id_cliente_principal;

    DELETE FROM clientes WHERE id_cliente = p_id_cliente_duplicado;

    COMMIT;
END$$

-- 14. Asigna o cambia el proveedor de un producto
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT
)
BEGIN
    UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
END$$

-- 15. Realiza una busqueda avanzada de productos con filtros
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(150),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(10,2),
    IN p_precio_max DECIMAL(10,2)
)
BEGIN
    SELECT * FROM productos
    WHERE (p_nombre IS NULL OR nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR precio >= p_precio_min)
      AND (p_precio_max IS NULL OR precio <= p_precio_max)
      AND activo = TRUE;
END$$

-- 16. Devuelve un conjunto de KPIs para un panel de administracion
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT SUM(total) FROM ventas WHERE DATE(fecha_venta) = CURDATE()) AS ventas_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE()) AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Pendiente de Pago') AS pedidos_pendientes,
        (SELECT COUNT(*) FROM productos WHERE stock < stock_minimo) AS productos_bajo_stock;
END$$

-- 17. Simula el procesamiento de un pago para una venta
CREATE PROCEDURE sp_ProcesarPago(IN p_id_venta INT)
BEGIN
    UPDATE ventas SET estado = 'Procesando' WHERE id_venta = p_id_venta AND estado = 'Pendiente de Pago';
END$$

-- 18. Permite a un cliente anadir una resena a un producto que ha comprado
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_producto INT,
    IN p_id_cliente INT,
    IN p_calificacion INT,
    IN p_comentario TEXT
)
BEGIN
    DECLARE v_compro INT;
    SELECT COUNT(*) INTO v_compro
    FROM detalle_ventas dv
    JOIN ventas v ON v.id_venta = dv.id_venta
    WHERE v.id_cliente = p_id_cliente AND dv.id_producto = p_id_producto;

    IF v_compro = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El cliente no ha comprado este producto';
    ELSE
        INSERT INTO resenas_producto (id_producto, id_cliente, calificacion, comentario)
        VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
    END IF;
END$$

-- 19. Devuelve productos relacionados basados en compras de otros clientes
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT p.id_producto, p.nombre, COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas dv1
    JOIN detalle_ventas dv2 ON dv1.id_venta = dv2.id_venta AND dv1.id_producto <> dv2.id_producto
    JOIN productos p ON p.id_producto = dv2.id_producto
    WHERE dv1.id_producto = p_id_producto
    GROUP BY p.id_producto, p.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END$$

-- 20. Mueve uno o mas productos de una categoria a otra de forma segura
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_id_categoria_origen INT,
    IN p_id_categoria_destino INT
)
BEGIN
    DECLARE v_existe_destino INT;
    SELECT COUNT(*) INTO v_existe_destino FROM categorias WHERE id_categoria = p_id_categoria_destino;

    IF v_existe_destino = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La categoria destino no existe';
    ELSE
        UPDATE productos SET id_categoria = p_id_categoria_destino WHERE id_categoria = p_id_categoria_origen;
    END IF;
END$$

DELIMITER ;