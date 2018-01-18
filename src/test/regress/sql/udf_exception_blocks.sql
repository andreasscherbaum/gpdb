-- Test exception handling in UDFs

-- ALTER table success and failure case in function with exception
CREATE TABLE test_exception_error (a INTEGER NOT NULL);
INSERT INTO test_exception_error select * from generate_series(1, 100);

-- SUCCESS case
CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
    BEGIN
    ALTER TABLE test_exception_error set with ( reorganize='true') distributed randomly;
        EXCEPTION
            WHEN OTHERS THEN
            BEGIN
                RAISE NOTICE 'catching the exception ...';
            END;
    END;
END;
$$
LANGUAGE plpgsql;

SELECT test_plpgsql();
SELECT count(*) FROM test_exception_error;

INSERT INTO test_exception_error SELECT * FROM generate_series(101, 200);

-- FAILURE scenario
CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
    BEGIN
    ALTER TABLE test_exception_error set with ( reorganize='true') distributed randomly;
        INSERT INTO test_exception_error(a) VALUES(NULL);
        EXCEPTION
            WHEN OTHERS THEN
            BEGIN
                RAISE NOTICE 'catching the exception ...';
            END;
    END;
END;
$$
LANGUAGE plpgsql;

-- Raises expected Exception
SELECT test_plpgsql();
SELECT count(*) FROM test_exception_error;

-- INSERT into table case in function with exception
--

DROP TABLE IF EXISTS test_exception_error;
DROP FUNCTION IF EXISTS test_plpgsql();

CREATE TABLE test_exception_error (a INTEGER NOT NULL);

CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
    BEGIN
        INSERT INTO test_exception_error(a) VALUES(1), (2), (3), (NULL), (4), (5), (6), (7), (8), (9);
        EXCEPTION
       	    WHEN OTHERS THEN
            BEGIN
			    RAISE NOTICE 'catching the exception ...';
            END;
	END;
END;
$$
LANGUAGE plpgsql;

-- Raises unexpected Exception but should not fail the command
SELECT test_plpgsql();

-- Tests with create table failure in function with exception
-- 

-- Create schema needed

CREATE SCHEMA s1;
CREATE SCHEMA s2;

-- Creating function
CREATE OR REPLACE FUNCTION s1.column_type_override_gp() RETURNS integer AS
$$
	declare 
		v_source_schema character varying(30);
		v_source_table character varying(30);
	begin
		v_source_schema:='s2' ;
		v_source_table:='corrupted_catalog' ;

		-- Issue was not observed if we use schemaname with the newly renamed table in the below query
		execute('ALTER TABLE ' ||v_source_schema || '.'|| v_source_table || ' rename to ' || v_source_table ||'temp');
		-- The below query has raised exception 
	        execute('CREATE TABLE ' ||v_source_schema || '.'|| v_source_table ||'(feed_no char(10),feed_no char(10))WITH ( OIDS=FALSE ) DISTRIBUTED BY ( feed_no )');
		execute('DROP TABLE ' ||v_source_schema || '.'|| v_source_table ||'temp'); 
		RETURN 1;
	-- when exception section has not been used then the cleanup done successfully and the table has been created successfully from the next section 
	 exception
	      WHEN OTHERS THEN
		RAISE NOTICE 'EXCEPTION HIT !!!';
		RETURN 0;   
	end;
$$
LANGUAGE plpgsql SECURITY DEFINER;
 
CREATE TABLE s2.corrupted_catalog
(
  feed_no character varying(4000)
)
WITH ( OIDS=FALSE );

SELECT s1.column_type_override_gp();

SELECT oid, relname, relnatts FROM pg_class WHERE relname = 'corrupted_catalogtemp'
                       AND relnamespace = (SELECT oid from pg_namespace where nspname = 's2') ;

-- Tests exception not generated by sql statement, explicit BEGIN and COMMIT/ABORT in function with exception
-- 

CREATE TABLE test_trans_tab ( a int);

-- Exception hit case
CREATE OR REPLACE FUNCTION test_trans() RETURNS INT AS
$$
	DECLARE
		ct bigint;
	BEGIN
		 INSERT INTO test_trans_tab VALUES (1);
		 ct = 1/0;
		 INSERT INTO test_trans_tab VALUES (2);
	EXCEPTION WHEN OTHERS THEN
		RAISE NOTICE 'EXCEPTION HIT !!!';
		RETURN 0;
	END;
$$ 
LANGUAGE 'plpgsql';

-- Function called which hits exception in explicit transaction block which commits
BEGIN;
SELECT test_trans();
INSERT INTO test_trans_tab VALUES (3);
COMMIT;

SELECT * FROM test_trans_tab;

-- Function called which hits exception in explicit transaction block which aborts
BEGIN;
SELECT test_trans();
INSERT INTO test_trans_tab VALUES (4);
ABORT;

SELECT * FROM test_trans_tab;

-- Tests loop and update in function with exception
-- 

CREATE TABLE test_loop_tab (a INT NOT NULL, b TEXT);

CREATE FUNCTION insert_db(key INT, data TEXT) RETURNS VOID AS
$$
BEGIN
	LOOP
   	-- first try to update the key
	UPDATE test_loop_tab SET b = data WHERE a = key;
	IF found THEN
		RETURN;
	END IF;
	-- not there, so try to insert the key
	BEGIN
		INSERT INTO test_loop_tab(a,b) VALUES (NULL, data);
	RETURN;
	EXCEPTION WHEN OTHERS THEN
			INSERT INTO test_loop_tab(a,b) VALUES (2, 'dummy');
			INSERT INTO test_loop_tab(a,b) VALUES (key, 'dummy');
	END;
	END LOOP;
END;
$$
LANGUAGE plpgsql;

SELECT insert_db(1, 'david');
SELECT * from test_loop_tab;

INSERT INTO test_loop_tab select *,'abcdefghijklmnopqrstuvwxyz' from generate_series(1, 100);

CREATE OR REPLACE FUNCTION insert_db(flag INT) RETURNS INT AS
$$
DECLARE
	rec   record;
	x INT;
BEGIN
	FOR rec IN
	SELECT *
	FROM   test_loop_tab
	WHERE  a % 2 = 0
	LOOP
		x = rec.a * flag;
		IF x = 400 THEN
			INSERT INTO test_loop_tab VALUES (NULL);
		ELSE
			INSERT INTO test_loop_tab VALUES (rec.a);
		END IF;
	END LOOP;
	RETURN 1;
	EXCEPTION WHEN OTHERS THEN
	BEGIN
		INSERT INTO test_loop_tab VALUES (999), (9999), (99999);
		RAISE NOTICE 'Exception Hit !!!';
		RETURN -1;
	END;
END;
$$
LANGUAGE plpgsql;

SELECT insert_db(1);
SELECT count(*) FROM test_loop_tab;

SELECT insert_db(200);
SELECT count(*) FROM test_loop_tab;

-- Tests nested function blocks with exception
-- 
DROP FUNCTION IF EXISTS test_plpgsql() CASCADE;

CREATE TABLE test_nested_blocks_tab (a INTEGER NOT NULL);

INSERT INTO test_nested_blocks_tab SELECT * from generate_series(1, 100);

CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
    BEGIN
	    INSERT INTO test_nested_blocks_tab SELECT * from test_nested_blocks_tab;
        BEGIN
		INSERT INTO test_nested_blocks_tab(a) VALUES(1000),(NULL),(1001),(1002);
	        EXCEPTION
	       	    WHEN OTHERS THEN
	            BEGIN
			    RAISE NOTICE 'catching the exception ...1';
		    END;
	END;
        BEGIN
		INSERT INTO test_nested_blocks_tab VALUES (1), (NULL); 
	        EXCEPTION
	       	    WHEN OTHERS THEN
	            BEGIN
			    RAISE NOTICE 'catching the exception ...2';
		    END;
	END;
	    INSERT INTO test_nested_blocks_tab SELECT * from test_nested_blocks_tab;
        EXCEPTION
       	    WHEN OTHERS THEN
	    BEGIN
		RAISE NOTICE 'catching the exception ...3';
            END;
	END;
END;
$$
LANGUAGE plpgsql;

-- Raises unexpected Exception in function but cmd still should be successful
SELECT test_plpgsql();

SELECT count(*) from test_nested_blocks_tab;

-- Tests master only function execution with exception block
-- 

DROP FUNCTION IF EXISTS test_plpgsql() CASCADE;

CREATE TABLE test_master_only_function_tab (a INTEGER NOT NULL);

CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
	BEGIN
		PERFORM * from pg_class;
	EXCEPTION
		WHEN OTHERS THEN
		BEGIN
			RAISE NOTICE 'catching the exception ...';
		END;
	END;
END;
$$
LANGUAGE plpgsql;

INSERT INTO test_master_only_function_tab SELECT * FROM generate_series(1, 100);
SELECT test_plpgsql();

SELECT count(*) FROM test_master_only_function_tab;

-- Tests exception raised on master instead of segment in function with
-- exception 
--

CREATE OR REPLACE FUNCTION test_exception_block_fn() RETURNS VOID AS
$$
BEGIN
     CREATE TABLE test_exception_block(a int) DISTRIBUTED BY (a);
     VACUUM pg_type;
EXCEPTION WHEN OTHERS THEN
RAISE NOTICE '%', SQLSTATE;
end;
$$ LANGUAGE plpgsql;

SELECT test_exception_block_fn();

SELECT relname FROM pg_class WHERE relname = 'test_exception_block';
SELECT relname FROM gp_dist_random('pg_class') WHERE relname = 'test_exception_block';

-- Test explicit function call inside SAVEPOINT (sub-transaction)
BEGIN;
	SAVEPOINT SP1;
	SELECT test_exception_block_fn();
	ROLLBACK to SP1;
COMMIT;

SELECT relname FROM pg_class WHERE relname = 'test_exception_block';
SELECT relname FROM gp_dist_random('pg_class') WHERE relname = 'test_exception_block';

-- Test explicit function call inside SAVEPOINT (sub-transaction)
BEGIN;
	SAVEPOINT SP1;
	SELECT test_exception_block_fn();
	RELEASE SP1;
COMMIT;

SELECT relname FROM pg_class WHERE relname = 'test_exception_block';
SELECT relname FROM gp_dist_random('pg_class') WHERE relname = 'test_exception_block';

-- Tests invalid schema creation from function with exception
-- 

DROP FUNCTION IF EXISTS test_exception_block_fn() CASCADE;

-- create base table
CREATE TABLE test_invalid_schema_creation_tab
(
  f1 smallint,
  f2 smallint,
  f3 smallint
)
WITH ( OIDS=FALSE ) DISTRIBUTED BY (f1);

-- create function execution of which post fix avoids catalog corruption
-- without the fix, VIEW v1 used to get commited on segment and not on master
CREATE OR REPLACE FUNCTION test_exception_block_fn() RETURNS integer AS
$$
	begin
		-- this view definition is valid
		CREATE VIEW test_invalid_schema_creation_tab_v1 AS SELECT f1 FROM test_invalid_schema_creation_tab;
		-- this view definition is invalid
		CREATE VIEW test_invalid_schema_creation_tab_v2 AS SELECT f4 FROM test_invalid_schema_creation_tab;
		return 1;
	exception
		WHEN OTHERS THEN
		RAISE NOTICE 'EXCEPTION HIT !!!';
	        return 0;
		RAISE EXCEPTION 'ERROR 0';
	end;
$$
LANGUAGE plpgsql SECURITY DEFINER;

--execute the function
SELECT * FROM test_exception_block_fn();

SELECT relname FROM pg_class WHERE relname IN ('test_invalid_schema_creation_tab_v1','test_invalid_schema_creation_tab_v2');
-- no record returned i.e. v1 does not exist in the catalog

--let's try and create v1
CREATE VIEW test_invalid_schema_creation_tab_v1 AS SELECT f1 FROM test_invalid_schema_creation_tab;
  -- Should not throw ERROR:  relation "test_invalid_schema_creation_tab_v1" already exists

DROP VIEW test_invalid_schema_creation_tab_v1;

-- Function call from savepoint which commits
BEGIN;
	SAVEPOINT SP1;
	SELECT * FROM test_exception_block_fn();
	RELEASE SP1;
COMMIT;

SELECT relname FROM pg_class WHERE relname IN ('test_invalid_schema_creation_tab_v1','test_invalid_schema_creation_tab_v2');
-- no record returned i.e. v1 does not exist in the catalog

--let's try and create v1
CREATE VIEW test_invalid_schema_creation_tab_v1 AS SELECT f1 FROM test_invalid_schema_creation_tab;
  -- Should not throw ERROR:  relation "test_invalid_schema_creation_tab_v1" already exists

DROP VIEW test_invalid_schema_creation_tab_v1;


--  create function execution of which post fix avoids catalog corruption
CREATE OR REPLACE FUNCTION test_exception_block_fn() RETURNS integer AS
$$
	begin
		-- this view definition is valid
		CREATE VIEW test_invalid_schema_creation_tab_v1 AS SELECT f1 FROM test_invalid_schema_creation_tab;
		return 1;
	exception
		WHEN OTHERS THEN
		RAISE NOTICE 'EXCEPTION HIT !!!';
	        return 0;
		RAISE EXCEPTION 'ERROR 0';
	end;
$$
LANGUAGE plpgsql SECURITY DEFINER;


-- Function call from savepoint which aborts
BEGIN;
	SAVEPOINT SP1;
	SELECT * FROM test_exception_block_fn();
	ROLLBACK TO SP1;
COMMIT;

SELECT relname FROM pg_class WHERE relname IN ('test_invalid_schema_creation_tab_v1','test_invalid_schema_creation_tab_v2');
-- no record returned i.e. v1 does not exist in the catalog

--let's try and create v1
CREATE VIEW test_invalid_schema_creation_tab_v1 AS SELECT f1 FROM test_invalid_schema_creation_tab;
  -- Should not throw ERROR:  relation "test_exception_block_v1" already exists

-- Tests truncate table success and failure case in function with exception
-- 

DROP FUNCTION IF EXISTS test_plpgsql() CASCADE;

CREATE TABLE test_truncate_tab (a INTEGER NOT NULL);
INSERT INTO test_truncate_tab select * from generate_series(1, 100);

-- SUCCESS case
CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
	TRUNCATE TABLE test_truncate_tab;
	INSERT INTO test_truncate_tab select * from generate_series(100, 150);
EXCEPTION WHEN OTHERS THEN
	RAISE NOTICE 'catching the exception ...';
END;
$$
LANGUAGE plpgsql;

SELECT test_plpgsql();
SELECT count(*) FROM test_truncate_tab;

INSERT INTO test_truncate_tab SELECT * FROM generate_series(150, 200);

-- FAILURE scenario
CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
	TRUNCATE TABLE test_truncate_tab;
	INSERT INTO test_truncate_tab select * from generate_series(200, 250);
	INSERT INTO test_truncate_tab(a) VALUES(NULL);
EXCEPTION WHEN OTHERS THEN
	RAISE NOTICE 'catching the exception ...';
END;
$$
LANGUAGE plpgsql;

-- Raises Exception
SELECT test_plpgsql();
SELECT count(*) FROM test_truncate_tab;
INSERT INTO test_truncate_tab select * from generate_series(250, 300);

-- FAILURE scenario
CREATE OR REPLACE FUNCTION test_plpgsql() RETURNS VOID AS
$$
BEGIN
	INSERT INTO test_truncate_tab select * from generate_series(300, 350);
	INSERT INTO test_truncate_tab(a) VALUES(NULL);
EXCEPTION WHEN OTHERS THEN
	BEGIN
		TRUNCATE TABLE test_truncate_tab;
		RAISE NOTICE 'catching the exception ...';
	END;
END;
$$
LANGUAGE plpgsql;

-- Raises Exception
SELECT test_plpgsql();
SELECT count(*) FROM test_truncate_tab;
INSERT INTO test_truncate_tab select * from generate_series(350, 400);
SELECT count(*) FROM test_truncate_tab;

