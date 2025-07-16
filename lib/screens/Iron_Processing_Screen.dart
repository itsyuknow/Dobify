-- User Addresses Table
CREATE TABLE user_addresses (
id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
address_type TEXT NOT NULL,
full_address TEXT NOT NULL,
latitude DECIMAL(10, 8),
longitude DECIMAL(11, 8),
landmark TEXT,
area TEXT,
city TEXT,
pincode TEXT,
is_default BOOLEAN DEFAULT FALSE,
created_at TIMESTAMPTZ DEFAULT NOW(),
updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Delivery Slots Table
CREATE TABLE delivery_slots (
id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
pickup_slot_start TIME NOT NULL,
pickup_slot_end TIME NOT NULL,
delivery_type TEXT NOT NULL CHECK (delivery_type IN ('Standard', 'Express')),
delivery_slot_start TIME NOT NULL,
delivery_slot_end TIME NOT NULL,
is_active BOOLEAN DEFAULT TRUE,
created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Orders Table
CREATE TABLE user_orders (
id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
order_items JSONB NOT NULL,
address_id UUID REFERENCES user_addresses(id),
pickup_slot_id UUID REFERENCES delivery_slots(id),
delivery_type TEXT NOT NULL CHECK (delivery_type IN ('Standard', 'Express')),
pickup_date DATE NOT NULL,
delivery_date DATE NOT NULL,
subtotal DECIMAL(10, 2) NOT NULL,
platform_fee DECIMAL(10, 2) DEFAULT 0,
service_tax DECIMAL(10, 2) DEFAULT 0,
delivery_fee DECIMAL(10, 2) DEFAULT 0,
discount DECIMAL(10, 2) DEFAULT 0,
total_amount DECIMAL(10, 2) NOT NULL,
coupon_code TEXT,
order_status TEXT DEFAULT 'pending',
payment_status TEXT DEFAULT 'pending',
created_at TIMESTAMPTZ DEFAULT NOW(),
updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert Sample Delivery Slots
INSERT INTO delivery_slots (pickup_slot_start, pickup_slot_end, delivery_type, delivery_slot_start, delivery_slot_end) VALUES
-- Standard Delivery Slots
('08:00', '10:00', 'Standard', '02:00', '04:00'),
('08:00', '10:00', 'Standard', '04:00', '06:00'),
('08:00', '10:00', 'Standard', '06:00', '08:00'),
('08:00', '10:00', 'Standard', '08:00', '10:00'),

('10:00', '12:00', 'Standard', '04:00', '06:00'),
('10:00', '12:00', 'Standard', '06:00', '08:00'),
('10:00', '12:00', 'Standard', '08:00', '10:00'),

('12:00', '14:00', 'Standard', '06:00', '08:00'),
('12:00', '14:00', 'Standard', '08:00', '10:00'),

('14:00', '16:00', 'Standard', '08:00', '10:00'),

('16:00', '18:00', 'Standard', '08:00', '10:00'),

-- Express Delivery Slots
('08:00', '10:00', 'Express', '12:00', '14:00'),
('08:00', '10:00', 'Express', '14:00', '16:00'),
('08:00', '10:00', 'Express', '16:00', '18:00'),
('08:00', '10:00', 'Express', '18:00', '20:00'),
('08:00', '10:00', 'Express', '20:00', '22:00'),

('10:00', '12:00', 'Express', '14:00', '16:00'),
('10:00', '12:00', 'Express', '16:00', '18:00'),
('10:00', '12:00', 'Express', '18:00', '20:00'),
('10:00', '12:00', 'Express', '20:00', '22:00'),

('12:00', '14:00', 'Express', '16:00', '18:00'),
('12:00', '14:00', 'Express', '18:00', '20:00'),
('12:00', '14:00', 'Express', '20:00', '22:00'),

('14:00', '16:00', 'Express', '18:00', '20:00'),
('14:00', '16:00', 'Express', '20:00', '22:00'),

('16:00', '18:00', 'Express', '20:00', '22:00');

-- Enable RLS
ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_orders ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own addresses" ON user_addresses
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own addresses" ON user_addresses
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own addresses" ON user_addresses
FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own addresses" ON user_addresses
FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own orders" ON user_orders
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own orders" ON user_orders
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own orders" ON user_orders
FOR UPDATE USING (auth.uid() = user_id);

-- Allow public read access to delivery slots
CREATE POLICY "Public can view delivery slots" ON delivery_slots
FOR SELECT USING (true);

-- Create indexes for better performance
CREATE INDEX idx_user_addresses_user_id ON user_addresses(user_id);
CREATE INDEX idx_user_orders_user_id ON user_orders(user_id);
CREATE INDEX idx_delivery_slots_type ON delivery_slots(delivery_type);
CREATE INDEX idx_delivery_slots_pickup ON delivery_slots(pickup_slot_start, pickup_slot_end);

-- Function to get available delivery slots for a pickup slot
CREATE OR REPLACE FUNCTION get_delivery_slots_for_pickup(
pickup_start TIME,
pickup_end TIME,
delivery_type_param TEXT
)
RETURNS TABLE(
id UUID,
delivery_slot_start TIME,
delivery_slot_end TIME
) AS $$
BEGIN
RETURN QUERY
SELECT ds.id, ds.delivery_slot_start, ds.delivery_slot_end
FROM delivery_slots ds
WHERE ds.pickup_slot_start = pickup_start
AND ds.pickup_slot_end = pickup_end
AND ds.delivery_type = delivery_type_param
AND ds.is_active = TRUE
ORDER BY ds.delivery_slot_start;
END;
$$ LANGUAGE plpgsql;


