-- =====================================================
-- 03_Funciones.sql
-- 20 funciones almacenadas
-- =====================================================
USE E_commerce;

DELIMITER $$

-- 1. Monto total de una venta
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta$$
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    SELECT SUM(cantidad * precio_unitario_congelado) INTO v_total
    FROM detalles_ventas WHERE id_venta = p_id_venta;
    RETURN COALESCE(v_total, 0);
END$$

-- 2. Valida si hay stock suficiente
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock$$
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    RETURN COALESCE(v_stock >= p_cantidad, FALSE);
END$$

-- 3. Precio actual de un producto
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto$$
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
    RETURN v_precio;
END$$

-- 4. Edad de un cliente
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente$$
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_fecha_nac DATE;
    SELECT fecha_nacimiento INTO v_fecha_nac FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_fecha_nac IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());
END$$

-- 5. Nombre completo estandarizado
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto$$
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(200)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_nombre_completo VARCHAR(200);
    SELECT CONCAT(apellido, ', ', nombre) INTO v_nombre_completo
    FROM clientes WHERE id_cliente = p_id_cliente;
    RETURN v_nombre_completo;
END$$

-- 6. Cliente cuya primera compra fue en los últimos 30 días
DROP FUNCTION IF EXISTS fn_EsClienteNuevo$$
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN DATEDIFF(NOW(), v_primera_compra) <= 30;
END$$

-- 7. Costo de envío según peso
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio$$
CREATE FUNCTION fn_CalcularCostoEnvio(p_peso_total_kg DECIMAL(10,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    RETURN 5000 + (p_peso_total_kg * 2000);
END$$

-- 8. Aplica un porcentaje de descuento
DROP FUNCTION IF EXISTS fn_AplicarDescuento$$
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(12,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN p_monto - (p_monto * (p_porcentaje / 100));
END$$

-- 9. Fecha de la última compra
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra$$
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_fecha;
END$$

-- 10. Valida formato de correo electrónico
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail$$
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    RETURN REGEXP_LIKE(p_email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$', 'c');
END$$

-- 11. Nombre de la categoría de un producto
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria$$
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_nombre_categoria VARCHAR(100);
    SELECT c.nombre INTO v_nombre_categoria
    FROM productos p JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE p.id_producto = p_id_producto;
    RETURN v_nombre_categoria;
END$$

-- 12. Número total de compras de un cliente (sin contar canceladas)
DROP FUNCTION IF EXISTS fn_ContarVentasCliente$$
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_total;
END$$

-- 13. Días desde la última compra
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra$$
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_fecha IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(NOW(), v_fecha);
END$$

-- 14. Estado de lealtad (Bronce, Plata, Oro)
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad$$
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(20)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_gasto DECIMAL(12,2);
    SELECT COALESCE(total_gastado, 0) INTO v_gasto FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_gasto >= 1000000 THEN
        RETURN 'Oro';
    ELSEIF v_gasto >= 300000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END$$

-- 15. Genera un SKU (prefijo de categoría + nombre + número aleatorio)
DROP FUNCTION IF EXISTS fn_GenerarSKU$$
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(150), p_id_categoria INT)
RETURNS VARCHAR(50)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_prefijo VARCHAR(10);
    SELECT UPPER(LEFT(nombre, 3)) INTO v_prefijo FROM categorias WHERE id_categoria = p_id_categoria;
    RETURN CONCAT('SKU-', COALESCE(v_prefijo, 'GEN'), '-',
                  UPPER(LEFT(REPLACE(p_nombre, ' ', ''), 4)), '-', LPAD(FLOOR(RAND() * 1000), 3, '0'));
END$$

-- 16. IVA sobre un monto
DROP FUNCTION IF EXISTS fn_CalcularIVA$$
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2), p_tasa_iva DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_monto * (p_tasa_iva / 100), 2);
END$$

-- 17. Stock total de una categoría
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria$$
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT SUM(stock) INTO v_total FROM productos WHERE id_categoria = p_id_categoria;
    RETURN COALESCE(v_total, 0);
END$$

-- 18. Fecha estimada de entrega según la ciudad del cliente
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega$$
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_dias INT;
    SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_ciudad = 'Bucaramanga' THEN
        SET v_dias = 2;
    ELSEIF v_ciudad IN ('Bogota', 'Medellin') THEN
        SET v_dias = 3;
    ELSE
        SET v_dias = 5;
    END IF;
    RETURN DATE_ADD(CURDATE(), INTERVAL v_dias DAY);
END$$

-- 19. Conversión de moneda con tasa fija
DROP FUNCTION IF EXISTS fn_ConvertirMoneda$$
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(12,2), p_tasa_cambio DECIMAL(10,4))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END$$

-- 20. Complejidad de contraseña (longitud, mayúscula, número)
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena$$
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF LENGTH(p_contrasena) < 8 THEN
        RETURN FALSE;
    ELSEIF NOT REGEXP_LIKE(p_contrasena, '[A-Z]', 'c') THEN
        RETURN FALSE;
    ELSEIF NOT REGEXP_LIKE(p_contrasena, '[0-9]') THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END$$

DELIMITER ;