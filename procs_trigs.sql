create or replace procedure log_restock_alert (product_id in number, product_name in varchar2) is
begin
dbms_output.put_line('Restock Needed: Product ' || product_name || ' ID: ' || product_id);
end;
/


create or replace procedure check_stock_level (p in number, new_stock_level in number) is
restock_level constant number:=50;
pn varchar2(255);
begin
select product_name into pn from product where product_id = p;
if new_stock_level < restock_level then
log_restock_alert(p, pn);
end if;
end;
/

CREATE OR REPLACE TRIGGER low_stock_alert
FOR UPDATE ON PRODUCT
COMPOUND TRIGGER
  -- Define collections to store product_id and quantity_available
  TYPE product_id_tab IS TABLE OF NUMBER;
  TYPE quantity_available_tab IS TABLE OF NUMBER;
  
  product_ids product_id_tab := product_id_tab();
  quantities quantity_available_tab := quantity_available_tab();
  
  BEFORE EACH ROW IS
  BEGIN
    -- Store product_id and quantity_available for each row being updated
    product_ids.EXTEND;
    quantities.EXTEND;
    product_ids(product_ids.LAST) := :OLD.product_id;
    quantities(quantities.LAST) := :NEW.quantity_available;
  END BEFORE EACH ROW;
  
  AFTER STATEMENT IS
  BEGIN
    -- Process the stored data after the update statement completes
    FOR i IN 1..product_ids.COUNT LOOP
      check_stock_level(product_ids(i), quantities(i));
    END LOOP;
  END AFTER STATEMENT;
END low_stock_alert;
/

-------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE update_customer_spending_for_order (p_order_id IN NUMBER) IS
BEGIN
  -- Update customer spending with the total purchase amount for the specified order
  UPDATE customer c
  SET total_amount_spent = total_amount_spent + (
    SELECT SUM(o.quantity_required * p.price_per_unit)
    FROM orders o
    JOIN product p ON o.product_id = p.product_id
    WHERE o.order_id = p_order_id
  )
  WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.order_id = p_order_id
    AND c.customer_id = o.customer_id
  );
  
  -- Commit the changes (optional, depending on transaction requirements)
  COMMIT;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Order ID ' || p_order_id || ' not found.');
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/


CREATE OR REPLACE PROCEDURE update_employee_sales_for_order (p_order_id IN NUMBER) IS
BEGIN
  -- Update employee sales with the total purchase amount for the specified order
  UPDATE employee e
  SET total_assisted_sales = total_assisted_sales + (
    SELECT SUM(o.quantity_required * p.price_per_unit)
    FROM orders o
    JOIN product p ON o.product_id = p.product_id
    WHERE o.order_id = p_order_id
  )
  WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.order_id = p_order_id
    AND e.employee_id = o.employee_id
  );
  
  -- Commit the changes (optional, depending on transaction requirements)
  COMMIT;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Order ID ' || p_order_id || ' not found.');
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE update_inventory_for_order (
  p_Order_ID IN NUMBER
)
IS
BEGIN
  -- Loop through all items in the order and update inventory for each item
  FOR order_item IN (
    SELECT product_id, quantity_required
    FROM orders
    WHERE order_id = p_Order_ID
  ) LOOP
    -- Call the update_inventory procedure for each item
    update_inventory(order_item.product_id, order_item.quantity_required);
  END LOOP;
END;
/

CREATE OR REPLACE PROCEDURE update_inventory (
  p_Product_ID IN NUMBER,
  p_Quantity_Required IN NUMBER
)
IS
BEGIN
  -- Update the Quantity_Available for the specified Product_ID
  UPDATE PRODUCT
  SET Quantity_Available = Quantity_Available - p_Quantity_Required
  WHERE Product_ID = p_Product_ID;
  
  -- Optionally, you can include additional validation or error handling logic here
  -- For example, check if the inventory quantity is sufficient before updating
  -- You may also handle any potential exceptions or errors that occur during the update
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    -- Handle case where the specified Product_ID is not found
    DBMS_OUTPUT.PUT_LINE('Product with ID ' || p_Product_ID || ' not found.');
  WHEN OTHERS THEN
    -- Log or handle other exceptions
    DBMS_OUTPUT.PUT_LINE('An error occurred while updating inventory for Product_ID: ' || p_Product_ID);
    RAISE; -- Re-raise the exception for further error handling at a higher level
END;
/

CREATE OR REPLACE PROCEDURE update_inventory_for_order (
  p_Order_ID IN NUMBER
)
IS
BEGIN
  -- Loop through all items in the order and update inventory for each item
  FOR order_item IN (
    SELECT product_id, quantity_required
    FROM orders
    WHERE order_id = p_Order_ID
  ) LOOP
    -- Call the update_inventory procedure for each item
    update_inventory(order_item.product_id, order_item.quantity_required);
  END LOOP;
END;
/


CREATE OR REPLACE TRIGGER update_on_sale
AFTER INSERT ON orders
FOR EACH ROW
DECLARE
  v_Order_ID NUMBER;
BEGIN
  -- Get the order ID from the inserted row
  v_Order_ID := :new.order_id;
  
  -- Call separate procedures to update related entities based on the new order
  update_inventory_for_order(v_Order_ID);
  update_employee_sales_for_order(v_Order_ID);
  update_customer_spending_for_order(v_Order_ID);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/

-------------------------------------------------------------------------------------------

create or replace procedure update_inventory(id in number, q in number) is
begin
update product set quantity_available=quantity_available-q where product_id=id;
--dbms_output.put_line('EXECUTED');
end;
/

create or replace procedure update_spending(id in number, t in number) is
begin
update customer set total_amount_spent=total_amount_spent+t where customer_id=id;
update customer set reward_points=reward_points+t/100 where customer_id=id;
--dbms_output.put_line('EXECUTED');
end;
/

create or replace procedure update_tas(id in number, t in number) is
begin
update employee set total_assisted_sales=total_assisted_sales+t where employee_id=id;
--dbms_output.put_line('EXECUTED');
end;
/

create or replace trigger sale
after insert on orders
for each row
declare
pid number;
cid number;
eid number;
q number;
t number;
begin
pid:=:new.product_id;
q:=:new.quantity_required;
t:=:new.total_order_value;
cid:=:new.customer_id;
eid:=:new.employee_id;
--dbms_output.put_line('Product ID: ' || pid);
--dbms_output.put_line('Quantity Required: ' || q);
update_inventory(pid,q);
update_spending(cid,t);
update_tas(eid,t);
--update product set quantity_available=quantity_available-q where product_id=pid;
--dbms_output.put_line(q);
end;
/

-------------------------------------------------------------------------------------------

create or replace trigger bonus
after insert on product
declare
ma number;
ma_id number;
begin
select max(total_assisted_sales) into ma from employee;
select employee_id into ma_id from employee where total_assisted_sales=ma;
dbms_output.put_line('Best Employee ID: '||ma_id);
end;
/






