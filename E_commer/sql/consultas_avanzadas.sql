-- =====================================================
-- 02_Consultas_Avanzadas.sql
-- 20 consultas analíticas
-- =====================================================
USE E_commerce;

-- 1. Top 10 Productos Más Vendidos
SELECT p.id_producto, p.nombre,
       SUM(dv.cantidad) AS unidades_vendidas,
       SUM(dv.cantidad * dv.precio_unitario_congelado) AS ingresos_totales
FROM productos p
JOIN detalles_ventas dv ON dv.id_producto = p.id_producto
JOIN ventas v ON v.id_venta = dv.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_totales DESC
LIMIT 10;

-- 2. Productos con Bajas Ventas (10% inferior)
WITH VentasPorProducto AS (
    SELECT p.id_producto, p.nombre,
           COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas,
           ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(dv.cantidad), 0) ASC) AS ranking,
           COUNT(*) OVER () AS total_productos
    FROM productos p
    LEFT JOIN detalles_ventas dv ON dv.id_producto = p.id_producto
    GROUP BY p.id_producto, p.nombre
)
SELECT id_producto, nombre, unidades_vendidas
FROM VentasPorProducto
WHERE ranking <= GREATEST(1, ROUND(total_productos * 0.10))
ORDER BY unidades_vendidas ASC;

-- 3. Clientes VIP (Mayores compradores)
SELECT c.id_cliente, c.nombre, c.apellido, SUM(v.total) AS gasto_total
FROM clientes c
JOIN ventas v ON v.id_cliente = c.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY gasto_total DESC
LIMIT 5;

-- 4. Análisis de Ventas Mensuales
SELECT YEAR(fecha_venta) AS anio, MONTH(fecha_venta) AS mes, SUM(total) AS total_vendido
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY YEAR(fecha_venta), MONTH(fecha_venta)
ORDER BY anio, mes;

-- 5. Crecimiento de Clientes
SELECT YEAR(fecha_registro) AS anio, QUARTER(fecha_registro) AS trimestre, COUNT(*) AS nuevos_clientes
FROM clientes
GROUP BY YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY anio, trimestre;

-- 6. Tasa de Compra Repetida
SELECT ROUND(100.0 * SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_clientes_recurrentes
FROM (
    SELECT id_cliente, COUNT(*) AS num_compras
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
) AS resumen;

-- 7. Productos Comprados Juntos Frecuentemente
SELECT dv1.id_producto AS producto_a, dv2.id_producto AS producto_b, COUNT(*) AS veces_juntos
FROM detalles_ventas dv1
JOIN detalles_ventas dv2 ON dv1.id_venta = dv2.id_venta AND dv1.id_producto < dv2.id_producto
JOIN ventas v ON v.id_venta = dv1.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY dv1.id_producto, dv2.id_producto
ORDER BY veces_juntos DESC;

-- 8. Rotación de Inventario por Categoría
SELECT cat.id_categoria, cat.nombre,
       COALESCE(vt.unidades_vendidas, 0) AS unidades_vendidas,
       s.stock_actual,
       ROUND(COALESCE(vt.unidades_vendidas, 0) / NULLIF(s.stock_actual, 0), 2) AS tasa_rotacion
FROM categorias cat
JOIN (SELECT id_categoria, SUM(stock) AS stock_actual
      FROM productos GROUP BY id_categoria) s ON s.id_categoria = cat.id_categoria
LEFT JOIN (SELECT p.id_categoria, SUM(dv.cantidad) AS unidades_vendidas
           FROM productos p
           JOIN detalles_ventas dv ON dv.id_producto = p.id_producto
           JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
           GROUP BY p.id_categoria) vt ON vt.id_categoria = cat.id_categoria;

-- 9. Productos que Necesitan Reabastecimiento (stock menor a 10)
SELECT id_producto, nombre, stock
FROM productos
WHERE stock < 10 AND activo = TRUE
ORDER BY stock ASC;

-- 10. Clientes sin compras en los últimos 30 días
SELECT c.id_cliente, c.nombre, c.apellido, c.fecha_registro
FROM clientes c
LEFT JOIN ventas v ON v.id_cliente = c.id_cliente
    AND v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 30 DAY)
WHERE v.id_venta IS NULL;

-- 11. Rendimiento de Proveedores
SELECT pr.id_proveedor, pr.nombre,
       SUM(dv.cantidad * dv.precio_unitario_congelado) AS ingresos_generados
FROM proveedores pr
JOIN productos p ON p.id_proveedor = pr.id_proveedor
JOIN detalles_ventas dv ON dv.id_producto = p.id_producto
JOIN ventas v ON v.id_venta = dv.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY ingresos_generados DESC;

-- 12. Análisis Geográfico de Ventas
SELECT c.ciudad AS ubicacion, SUM(v.total) AS total_ventas, COUNT(v.id_venta) AS numero_ventas
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.ciudad
ORDER BY total_ventas DESC;

-- 13. Ventas por Hora del Día
SELECT HOUR(fecha_venta) AS hora, COUNT(*) AS numero_ventas, SUM(total) AS total_vendido
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY HOUR(fecha_venta)
ORDER BY numero_ventas DESC;

-- 14. Impacto de Promociones (producto 1, enero 2026)
SELECT
    SUM(CASE WHEN v.fecha_venta < '2026-01-01' THEN dv.cantidad ELSE 0 END) AS unidades_antes,
    SUM(CASE WHEN v.fecha_venta >= '2026-01-01' AND v.fecha_venta < '2026-02-01' THEN dv.cantidad ELSE 0 END) AS unidades_durante,
    SUM(CASE WHEN v.fecha_venta >= '2026-02-01' THEN dv.cantidad ELSE 0 END) AS unidades_despues
FROM detalles_ventas dv
JOIN ventas v ON v.id_venta = dv.id_venta
WHERE dv.id_producto = 1 AND v.estado <> 'Cancelado';

-- 15. Análisis de Cohorte (retención mensual desde la primera compra)
SELECT DATE_FORMAT(pc.fecha_primera, '%Y-%m') AS mes_cohort,
       DATE_FORMAT(v.fecha_venta, '%Y-%m') AS mes_actividad,
       COUNT(DISTINCT v.id_cliente) AS clientes_activos
FROM ventas v
JOIN (SELECT id_cliente, MIN(fecha_venta) AS fecha_primera
      FROM ventas WHERE estado <> 'Cancelado' GROUP BY id_cliente) AS pc
     ON pc.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY mes_cohort, mes_actividad
ORDER BY mes_cohort, mes_actividad;

-- 16. Margen de Beneficio por Producto
SELECT id_producto, nombre, precio, costo,
       (precio - costo) AS margen_absoluto,
       ROUND(((precio - costo) / precio) * 100, 2) AS margen_porcentual
FROM productos
ORDER BY margen_porcentual DESC;

-- 17. Tiempo Promedio Entre Compras (por cliente)
SELECT id_cliente, AVG(DATEDIFF(fecha_siguiente, fecha_venta)) AS dias_promedio_entre_compras
FROM (
    SELECT id_cliente, fecha_venta,
           LEAD(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS fecha_siguiente
    FROM ventas
    WHERE estado <> 'Cancelado'
) AS sub
WHERE fecha_siguiente IS NOT NULL
GROUP BY id_cliente;

-- 18. Productos Más Vistos vs. Comprados
SELECT p.id_producto, p.nombre,
       COALESCE(vi.vistas, 0) AS vistas,
       COALESCE(co.unidades, 0) AS unidades_compradas,
       ROUND(100 * COALESCE(co.unidades, 0) / NULLIF(vi.vistas, 0), 2) AS conversion_pct
FROM productos p
LEFT JOIN (SELECT id_producto, COUNT(*) AS vistas FROM producto_vistas GROUP BY id_producto) vi
       ON vi.id_producto = p.id_producto
LEFT JOIN (SELECT dv.id_producto, SUM(dv.cantidad) AS unidades
           FROM detalles_ventas dv
           JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
           GROUP BY dv.id_producto) co ON co.id_producto = p.id_producto
ORDER BY vistas DESC;

-- 19. Segmentación de Clientes (RFM)
SELECT c.id_cliente, c.nombre, c.apellido,
       DATEDIFF(NOW(), MAX(v.fecha_venta)) AS recencia_dias,
       COUNT(v.id_venta) AS frecuencia,
       SUM(v.total) AS monetario
FROM clientes c
JOIN ventas v ON v.id_cliente = c.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY monetario DESC;

-- 20. Predicción de Demanda Simple (promedio mensual de los últimos 3 meses por categoría)
SELECT cat.id_categoria, cat.nombre, ROUND(AVG(m.total_unidades), 2) AS proyeccion_proximo_mes
FROM categorias cat
JOIN (
    SELECT p.id_categoria, DATE_FORMAT(v.fecha_venta, '%Y-%m') AS mes, SUM(dv.cantidad) AS total_unidades
    FROM detalles_ventas dv
    JOIN productos p ON p.id_producto = dv.id_producto
    JOIN ventas v ON v.id_venta = dv.id_venta
    WHERE v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 3 MONTH) AND v.estado <> 'Cancelado'
    GROUP BY p.id_categoria, mes
) AS m ON m.id_categoria = cat.id_categoria
GROUP BY cat.id_categoria, cat.nombre;