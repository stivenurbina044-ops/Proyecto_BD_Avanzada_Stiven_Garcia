# Proyecto de Base de Datos para un E-commerce

## Descripción

Este proyecto implementa una base de datos relacional en MySQL para una tienda en línea (`E_commerce`). Incluye el modelo de datos (categorías, proveedores, productos, clientes, ventas y detalles de venta) y la lógica avanzada que un sistema real necesita: consultas analíticas, funciones, procedimientos almacenados, triggers de validación y auditoría, eventos programados y un esquema de roles y permisos. El objetivo es demostrar el diseño, la integridad de los datos y la automatización de procesos de negocio directamente desde la base de datos.

## Requisitos

- MySQL **8.0.29 o superior** (se usa `CREATE PROCEDURE IF NOT EXISTS`).
- Un usuario con privilegios administrativos (por ejemplo `root`), ya que los scripts crean roles y usuarios y modifican variables globales.
- Cliente SQL: MySQL Workbench o la línea de comandos de `mysql`.

## Instrucciones de ejecución

Los scripts deben ejecutarse **en el orden indicado**, porque cada uno depende de objetos creados por los anteriores.

| Orden | Archivo | Qué hace |
|-------|---------|----------|
| 1 | `01_Esquema_y_Datos.sql` | Crea la base de datos `E_commerce`, las tablas y carga los datos iniciales. **Elimina y recrea las tablas principales**, por lo que borra los datos existentes. |
| 2 | `02_Consultas_Avanzadas.sql` | 20 consultas analíticas (top de productos, clientes VIP, cohortes, RFM, etc.). |
| 3 | `03_Funciones.sql` | 20 funciones almacenadas (cálculo de totales, IVA, lealtad, validaciones). |
| 4 | `04_Seguridad.sql` | Roles, usuarios, permisos, vistas de seguridad y tablas de auditoría. |
| 5 | `05_Triggers.sql` | Agrega columnas de apoyo y crea los triggers de validación y auditoría. |
| 6 | `06_Eventos.sql` | Tablas de reportes y 20 eventos programados (activa `event_scheduler`). |
| 7 | `07_Procedimientos_Almacenados.sql` | 20 procedimientos almacenados (ventas, devoluciones, reportes, etc.). |

### Desde MySQL Workbench

Abrir cada archivo con **File → Open SQL Script** y ejecutarlo completo (rayo ⚡) en el orden de la tabla.

### Desde la línea de comandos

```bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p < 02_Consultas_Avanzadas.sql
mysql -u root -p < 03_Funciones.sql
mysql -u root -p < 04_Seguridad.sql
mysql -u root -p < 05_Triggers.sql
mysql -u root -p < 06_Eventos.sql
mysql -u root -p < 07_Procedimientos_Almacenados.sql
```

## Verificación rápida

Después de ejecutar todos los scripts, se puede comprobar que los objetos existen:

```sql
USE E_commerce;
SHOW TABLES;
SHOW TRIGGERS;
SHOW EVENTS;
SHOW FUNCTION STATUS WHERE Db = 'E_commerce';
SHOW PROCEDURE STATUS WHERE Db = 'E_commerce';
```

Ejemplos de prueba:

```sql
SELECT fn_CalcularTotalVenta(1);
CALL sp_ObtenerDashboardAdmin();
CALL sp_RealizarNuevaVenta(1, 1, 2);
```

## Modelo de datos

- `categorias` y `proveedores`: catálogos de apoyo.
- `productos`: precio, costo, stock, SKU, categoría y proveedor.
- `clientes`: datos de contacto y dirección de envío.
- `ventas`: encabezado de cada pedido (estado y total).
- `detalles_ventas`: productos de cada venta, con el precio congelado al momento de comprar.

## Notas de seguridad

Los usuarios creados en `04_Seguridad.sql` usan la contraseña de ejemplo `CambiarEstaClave123!`. **Debe cambiarse** antes de usar la base de datos fuera de un entorno de pruebas.

## Presentado por:
Stiven Urbina

