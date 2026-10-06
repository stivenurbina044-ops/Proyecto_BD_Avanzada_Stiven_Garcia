USE E_commerce;

-- 2. ALTER TABLE SEGURO: AÑADIR CAMPOS EN LA TABLA 'clientes'

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_agregar_columnas_inactividad_seguras$$

CREATE PROCEDURE sp_agregar_columnas_inactividad_seguras()
BEGIN
    -- Añadir fecha_ultima_compra si no existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() 
          AND table_name = 'clientes' 
          AND column_name = 'fecha_ultima_compra'
    ) THEN
        ALTER TABLE clientes ADD COLUMN fecha_ultima_compra DATETIME DEFAULT NULL;
    END IF;

    -- Añadir activo si no existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() 
          AND table_name = 'clientes' 
          AND column_name = 'activo'
    ) THEN
        ALTER TABLE clientes ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE;
    END IF;
END$$

DELIMITER ;

-- Ejecución y limpieza del procedimiento
CALL sp_agregar_columnas_inactividad_seguras();
DROP PROCEDURE IF EXISTS sp_agregar_columnas_inactividad_seguras;


-- 3. TRIGGER PARA ACTUALIZAR LA FECHA DE ÚLTIMA COMPRA EN CLIENTES


DELIMITER $$

DROP TRIGGER IF EXISTS trg_actualizar_fecha_ultima_compra$$

CREATE TRIGGER trg_actualizar_fecha_ultima_compra
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> 'Cancelado' THEN
        UPDATE clientes
        SET fecha_ultima_compra = NEW.fecha_venta
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$

DELIMITER ;


-- 4. EVENTO PROGRAMADO: DESACTIVAR CUENTAS INACTIVAS

DELIMITER $$

DROP EVENT IF EXISTS evt_desactivar_cuentas_inactivas$$

CREATE EVENT evt_desactivar_cuentas_inactivas
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE clientes
    SET activo = FALSE
    WHERE activo = TRUE
      AND fecha_ultima_compra IS NOT NULL
      AND fecha_ultima_compra < DATE_SUB(NOW(), INTERVAL 2 YEAR);
END$$

DELIMITER ;

