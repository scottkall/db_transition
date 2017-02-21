INSERT INTO table2
SELECT * FROM table1;

CREATE TABLE adminClinical AS
SELECT *
FROM admin
INNER JOIN clinical
ON admin.pdx_id=clinical.pdx_id;

CREATE VIEW admin_clinical AS 
SELECT *
FROM admin
INNER JOIN clinical
ON admin.pdx_id=clinical.pdx_id;


SELECT *
FROM admin
INNER JOIN clinical
ON admin.pdx_id=clinical.pdx_id
LIMIT 2;

SELECT *
FROM admin
INNER JOIN tumor
ON admin.pdx_id=tumor.pdx_id
LIMIT 2;
