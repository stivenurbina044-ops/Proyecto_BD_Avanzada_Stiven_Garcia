USE E_commerce;

DELIMITER $$

-- 1. Calcula el monto total de una venta especifica
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    SELECT SUM(cantidad * precio_unitario_congelado) INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;
    RETURN COALESCE(v_total, 0);
END$$

-- 2. Valida si hay stock suficiente para un producto
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    RETURN v_stock >= p_cantidad;
END$$

-- 3. Devuelve el precio actual de un producto
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
    RETURN v_precio;
END$$

-- 4. Calcula la edad de un cliente a partir de su fecha de nacimiento
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha_nac DATE;
    SELECT fecha_nacimiento INTO v_fecha_nac FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_fecha_nac IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());
END$$

-- 5. Devuelve el nombre y apellido de un cliente en formato estandarizado
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(200)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre_completo VARCHAR(200);
    SELECT CONCAT(apellido, ', ', nombre) INTO v_nombre_completo
    FROM clientes WHERE id_cliente = p_id_cliente;
    RETURN v_nombre_completo;
END$$

-- 6. Devuelve VERDADERO si el cliente realizo su primera compra en los ultimos 30 dias
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra FROM ventas WHERE id_cliente = p_id_cliente;
    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN DATEDIFF(NOW(), v_primera_compra) <= 30;
END$$

-- 7. Calcula el costo de envio basado en el peso total (parametro simple, sin tabla de pesos)
CREATE FUNCTION fn_CalcularCostoEnvio(p_peso_total_kg DECIMAL(10,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE v_costo DECIMAL(10,2);
    SET v_costo = 5000 + (p_peso_total_kg * 2000);
    RETURN v_costo;
END$$

-- 8. Aplica un porcentaje de descuento a un monto dado
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(12,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN p_monto - (p_monto * (p_porcentaje / 100));
END$$

-- 9. Devuelve la fecha de la ultima compra de un cliente
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha FROM ventas WHERE id_cliente = p_id_cliente;
    RETURN v_fecha;
END$$

-- 10. Comprueba si una cadena de texto tiene formato de correo electronico valido
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    RETURN p_email REGEXP '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END$$

-- 11. Devuelve el nombre de la categoria a partir del ID de un producto
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre_categoria VARCHAR(100);
    SELECT c.nombre INTO v_nombre_categoria
    FROM productos p
    JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE p.id_producto = p_id_producto;
    RETURN v_nombre_categoria;
END$$

-- 12. Cuenta el numero total de compras realizadas por un cliente
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total FROM ventas WHERE id_cliente = p_id_cliente;
    RETURN v_total;
END$$

-- 13. Devuelve el numero de dias transcurridos desde la ultima compra de un cliente
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha FROM ventas WHERE id_cliente = p_id_cliente;
    IF v_fecha IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(NOW(), v_fecha);
END$$

-- 14. Asigna un estado de lealtad (Bronce, Plata, Oro) segun el gasto total
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_gasto DECIMAL(12,2);
    SELECT total_gastado INTO v_gasto FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_gasto >= 1000000 THEN
        RETURN 'Oro';
    ELSEIF v_gasto >= 300000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END$$

-- 15. Genera un codigo de producto (SKU) unico basado en nombre y categoria
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(150), p_id_categoria INT)
RETURNS VARCHAR(50)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_prefijo VARCHAR(10);
    DECLARE v_sku VARCHAR(50);
    SELECT UPPER(LEFT(nombre, 3)) INTO v_prefijo FROM categorias WHERE id_categoria = p_id_categoria;
    SET v_sku = CONCAT('SKU-', COALESCE(v_prefijo, 'GEN'), '-', UPPER(LEFT(REPLACE(p_nombre, ' ', ''), 4)), '-', FLOOR(RAND() * 1000));
    RETURN v_sku;
END$$

-- 16. Calcula el impuesto (IVA) sobre el total de una venta
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2), p_tasa_iva DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_monto * (p_tasa_iva / 100), 2);
END$$

-- 17. Suma el stock de todos los productos de una categoria
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT SUM(stock) INTO v_total FROM productos WHERE id_categoria = p_id_categoria;
    RETURN COALESCE(v_total, 0);
END$$

-- 18. Calcula la fecha estimada de entrega segun la ciudad del cliente
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_dias INT;
    SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_ciudad = 'Bucaramanga' THEN
        SET v_dias = 2;
    ELSEIF v_ciudad IN ('Bogota','Medellin') THEN
        SET v_dias = 3;
    ELSE
        SET v_dias = 5;
    END IF;
    RETURN DATE_ADD(CURDATE(), INTERVAL v_dias DAY);
END$$

-- 19. Convierte un monto a otra moneda usando una tasa de cambio fija
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(12,2), p_tasa_cambio DECIMAL(10,4))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END$$

-- 20. Verifica si una contrasena cumple con criterios de seguridad (longitud, mayuscula, numero)
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF LENGTH(p_contrasena) < 8 THEN
        RETURN FALSE;
    ELSEIF p_contrasena NOT REGEXP '[A-Z]' THEN
        RETURN FALSE;
    ELSEIF p_contrasena NOT REGEXP '[0-9]' THEN
        RETURN FALSE;
    ELSE
        RETURN TRUE;
    END IF;
END$$

DELIMITER ;