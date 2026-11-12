-- Initial empty D1 schema generated from backend/app/models.py.
-- Schema only; this migration does not contain production data.

CREATE TABLE aiconfiguration (
	id INTEGER NOT NULL,
	selected_model VARCHAR(120) NOT NULL,
	updated_by_email VARCHAR(254),
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE aiinteraction (
	id INTEGER NOT NULL,
	requested_by_email VARCHAR(254) NOT NULL,
	user_role VARCHAR(24) NOT NULL,
	question VARCHAR NOT NULL,
	context_type VARCHAR(32) NOT NULL,
	context_id INTEGER,
	response_payload VARCHAR NOT NULL,
	proposed_action_type VARCHAR(60),
	proposed_action_payload VARCHAR,
	status VARCHAR(24) NOT NULL,
	confirmed_by_email VARCHAR(254),
	confirmed_at DATETIME,
	result_summary VARCHAR,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE appointment (
	id INTEGER NOT NULL,
	customer_id INTEGER NOT NULL,
	vehicle_id INTEGER,
	bay_id INTEGER,
	technician_user_id INTEGER,
	starts_at DATETIME NOT NULL,
	ends_at DATETIME NOT NULL,
	service_type VARCHAR(120) NOT NULL,
	notes VARCHAR,
	status VARCHAR(24) NOT NULL,
	google_event_id VARCHAR(200),
	sync_status VARCHAR(24) NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(bay_id) REFERENCES workshopbay (id),
	FOREIGN KEY(technician_user_id) REFERENCES user (id)
);

CREATE TABLE bulkimport (
	id VARCHAR(36) NOT NULL,
	kind VARCHAR(16) NOT NULL,
	filename VARCHAR(255) NOT NULL,
	created_by VARCHAR(254) NOT NULL,
	status VARCHAR(24) NOT NULL,
	payload VARCHAR NOT NULL,
	summary VARCHAR NOT NULL,
	created_at DATETIME NOT NULL,
	expires_at DATETIME NOT NULL,
	confirmed_at DATETIME,
	PRIMARY KEY (id)
);

CREATE TABLE calendarimportsettings (
	id INTEGER NOT NULL,
	calendar_id VARCHAR(250) NOT NULL,
	enabled BOOLEAN NOT NULL,
	last_synced_at DATETIME,
	PRIMARY KEY (id)
);

CREATE TABLE cashaccount (
	id INTEGER NOT NULL,
	name VARCHAR(80) NOT NULL,
	kind VARCHAR(24) NOT NULL,
	active BOOLEAN NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE cashclosure (
	id INTEGER NOT NULL,
	account_id INTEGER NOT NULL,
	status VARCHAR(16) NOT NULL,
	opening_amount_clp INTEGER NOT NULL,
	closing_amount_clp INTEGER,
	expected_amount_clp INTEGER,
	difference_clp INTEGER,
	notes VARCHAR(1000) NOT NULL,
	opened_by_email VARCHAR(254),
	closed_by_email VARCHAR(254),
	opened_at DATETIME NOT NULL,
	closed_at DATETIME,
	PRIMARY KEY (id),
	FOREIGN KEY(account_id) REFERENCES cashaccount (id)
);

CREATE TABLE cashmovement (
	id INTEGER NOT NULL,
	account_id INTEGER NOT NULL,
	direction VARCHAR(16) NOT NULL,
	amount_clp INTEGER NOT NULL,
	status VARCHAR(24) NOT NULL,
	source_type VARCHAR(40) NOT NULL,
	source_id INTEGER,
	payment_id INTEGER,
	customer_id INTEGER,
	vehicle_id INTEGER,
	work_order_id INTEGER,
	category VARCHAR(80) NOT NULL,
	note VARCHAR(1000) NOT NULL,
	reference VARCHAR(120),
	counterparty VARCHAR(160),
	reversal_of_id INTEGER,
	created_by_email VARCHAR(254),
	occurred_at DATETIME NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(account_id) REFERENCES cashaccount (id),
	FOREIGN KEY(payment_id) REFERENCES payment (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(reversal_of_id) REFERENCES cashmovement (id)
);

CREATE TABLE customer (
	id INTEGER NOT NULL,
	full_name VARCHAR(120) NOT NULL,
	rut VARCHAR(12),
	email VARCHAR(254),
	phone VARCHAR(30),
	notes VARCHAR,
	created_at DATETIME NOT NULL,
	archived_at DATETIME,
	PRIMARY KEY (id)
);

CREATE TABLE customeraccesstoken (
	id INTEGER NOT NULL,
	user_id INTEGER NOT NULL,
	customer_id INTEGER NOT NULL,
	purpose VARCHAR(24) NOT NULL,
	token_hash VARCHAR(64) NOT NULL,
	expires_at DATETIME NOT NULL,
	used_at DATETIME,
	sent_at DATETIME,
	requested_by_email VARCHAR(254),
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(user_id) REFERENCES user (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id)
);

CREATE TABLE customerengagementvisit (
	id INTEGER NOT NULL,
	customer_id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	channel VARCHAR(24) NOT NULL,
	visitor_hash VARCHAR(64) NOT NULL,
	window_start DATETIME NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_customer_engagement_visit UNIQUE (customer_id, vehicle_id, channel, visitor_hash, window_start),
	FOREIGN KEY(customer_id) REFERENCES customer (id)
);

CREATE TABLE diagnosticfinding (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	work_order_service_id INTEGER,
	scanner_report_id INTEGER,
	vehicle_id INTEGER NOT NULL,
	module VARCHAR(120) NOT NULL,
	dtc_code VARCHAR(32) NOT NULL,
	symptom VARCHAR(1000) NOT NULL,
	freeze_frame VARCHAR(4000) NOT NULL,
	measurements VARCHAR(4000) NOT NULL,
	test_performed VARCHAR(4000) NOT NULL,
	test_result VARCHAR(4000) NOT NULL,
	conclusion VARCHAR(4000) NOT NULL,
	technician_confirmed_at DATETIME,
	recorded_by_email VARCHAR(254) NOT NULL,
	created_at DATETIME NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(work_order_service_id) REFERENCES workorderservice (id),
	FOREIGN KEY(scanner_report_id) REFERENCES scannerreport (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id)
);

CREATE TABLE externalcalendarevent (
	id INTEGER NOT NULL,
	calendar_id VARCHAR(250) NOT NULL,
	event_id VARCHAR(250) NOT NULL,
	title VARCHAR(500) NOT NULL,
	description VARCHAR,
	starts_at DATETIME NOT NULL,
	ends_at DATETIME NOT NULL,
	all_day BOOLEAN NOT NULL,
	status VARCHAR(24) NOT NULL,
	google_updated_at DATETIME,
	imported_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_external_calendar_event UNIQUE (calendar_id, event_id)
);

CREATE TABLE externalimport (
	id INTEGER NOT NULL,
	provider VARCHAR(32) NOT NULL,
	external_id VARCHAR(500) NOT NULL,
	filename VARCHAR(255) NOT NULL,
	status VARCHAR(24) NOT NULL,
	scanner_report_id INTEGER,
	imported_by_email VARCHAR(254) NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_external_import_provider_id UNIQUE (provider, external_id),
	FOREIGN KEY(scanner_report_id) REFERENCES scannerreport (id)
);

CREATE TABLE googleintegrationconfig (
	id INTEGER NOT NULL,
	client_id VARCHAR(300) NOT NULL,
	encrypted_client_secret VARCHAR NOT NULL,
	redirect_uri VARCHAR(500) NOT NULL,
	drive_folder_id VARCHAR(250),
	calendar_id VARCHAR(250) NOT NULL,
	gmail_query VARCHAR(500) NOT NULL,
	updated_by_email VARCHAR(254) NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE inspection (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	work_order_service_id INTEGER,
	category VARCHAR(80) NOT NULL,
	item VARCHAR(120) NOT NULL,
	result VARCHAR(40) NOT NULL,
	notes VARCHAR,
	measured_value VARCHAR(80),
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(work_order_service_id) REFERENCES workorderservice (id)
);

CREATE TABLE inspectiontemplate (
	id INTEGER NOT NULL,
	"key" VARCHAR(60) NOT NULL,
	name VARCHAR(120) NOT NULL,
	service_type VARCHAR(80) NOT NULL,
	description VARCHAR,
	active BOOLEAN NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE inspectiontemplateitem (
	id INTEGER NOT NULL,
	template_id INTEGER NOT NULL,
	category VARCHAR(80) NOT NULL,
	item VARCHAR(120) NOT NULL,
	sort_order INTEGER NOT NULL,
	required BOOLEAN NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(template_id) REFERENCES inspectiontemplate (id)
);

CREATE TABLE installedpart (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	work_order_service_id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	product_id INTEGER,
	supplied_by VARCHAR(16) NOT NULL,
	name VARCHAR(160) NOT NULL,
	category VARCHAR(80) NOT NULL,
	brand VARCHAR(80) NOT NULL,
	part_number VARCHAR(100) NOT NULL,
	oem_number VARCHAR(100) NOT NULL,
	specifications VARCHAR(2000) NOT NULL,
	quantity FLOAT NOT NULL,
	status VARCHAR(20) NOT NULL,
	fitment_status VARCHAR(20) NOT NULL,
	verification_source VARCHAR(250) NOT NULL,
	vehicle_identity_signature VARCHAR(64) NOT NULL,
	evidence_id INTEGER,
	notes VARCHAR(2000) NOT NULL,
	recorded_by_email VARCHAR(254) NOT NULL,
	recorded_at DATETIME NOT NULL,
	installed_at DATETIME,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(work_order_service_id) REFERENCES workorderservice (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(product_id) REFERENCES product (id),
	FOREIGN KEY(evidence_id) REFERENCES workorderevidence (id)
);

CREATE TABLE integrationcredential (
	id INTEGER NOT NULL,
	provider VARCHAR(32) NOT NULL,
	encrypted_refresh_token VARCHAR NOT NULL,
	encrypted_access_token VARCHAR,
	access_token_expires_at DATETIME,
	granted_scopes VARCHAR NOT NULL,
	account_email VARCHAR(254),
	created_at DATETIME NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE inventorycountline (
	id INTEGER NOT NULL,
	session_id INTEGER NOT NULL,
	product_id INTEGER NOT NULL,
	expected_quantity FLOAT NOT NULL,
	counted_quantity FLOAT NOT NULL,
	note VARCHAR(1000) NOT NULL,
	counted_by_email VARCHAR(254),
	counted_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_inventory_count_line UNIQUE (session_id, product_id),
	FOREIGN KEY(session_id) REFERENCES inventorycountsession (id),
	FOREIGN KEY(product_id) REFERENCES product (id)
);

CREATE TABLE inventorycountsession (
	id INTEGER NOT NULL,
	code VARCHAR(32) NOT NULL,
	name VARCHAR(140) NOT NULL,
	status VARCHAR(24) NOT NULL,
	blind_count BOOLEAN NOT NULL,
	created_by_email VARCHAR(254),
	reviewed_by_email VARCHAR(254),
	created_at DATETIME NOT NULL,
	submitted_at DATETIME,
	applied_at DATETIME,
	PRIMARY KEY (id)
);

CREATE TABLE loyaltyredemption (
	id INTEGER NOT NULL,
	customer_id INTEGER NOT NULL,
	reward_id INTEGER NOT NULL,
	points_cost INTEGER NOT NULL,
	status VARCHAR(24) NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(reward_id) REFERENCES loyaltyreward (id)
);

CREATE TABLE loyaltyreward (
	id INTEGER NOT NULL,
	name VARCHAR(120) NOT NULL,
	description VARCHAR(400),
	points_cost INTEGER NOT NULL,
	active BOOLEAN NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE loyaltytransaction (
	id INTEGER NOT NULL,
	customer_id INTEGER NOT NULL,
	sale_id INTEGER,
	points INTEGER NOT NULL,
	kind VARCHAR(24) NOT NULL,
	note VARCHAR(250),
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(sale_id) REFERENCES sale (id)
);

CREATE TABLE maintenanceexecution (
	id INTEGER NOT NULL,
	plan_id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	work_order_id INTEGER,
	request_key VARCHAR(80) NOT NULL,
	plan_name VARCHAR(120) NOT NULL,
	mileage_km INTEGER NOT NULL,
	interval_km INTEGER,
	interval_days INTEGER,
	next_due_km INTEGER,
	next_due_at DATETIME,
	materials VARCHAR(4000) NOT NULL,
	oil_used VARCHAR(1000) NOT NULL,
	filters_used VARCHAR(2000) NOT NULL,
	notes VARCHAR(4000) NOT NULL,
	recorded_by VARCHAR(254) NOT NULL,
	performed_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	UNIQUE (plan_id, request_key),
	FOREIGN KEY(plan_id) REFERENCES maintenanceplan (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id)
);

CREATE TABLE maintenanceplan (
	id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	name VARCHAR(120) NOT NULL,
	category VARCHAR(32) NOT NULL,
	interval_km INTEGER,
	interval_days INTEGER,
	last_service_km INTEGER,
	last_service_at DATETIME NOT NULL,
	active BOOLEAN NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id)
);

CREATE TABLE marketingcampaign (
	id INTEGER NOT NULL,
	title VARCHAR(140) NOT NULL,
	message VARCHAR(1200) NOT NULL,
	audience VARCHAR(48) NOT NULL,
	status VARCHAR(24) NOT NULL,
	starts_at DATETIME,
	ends_at DATETIME,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE metaintegrationconfig (
	id INTEGER NOT NULL,
	app_id VARCHAR(100) NOT NULL,
	encrypted_app_secret VARCHAR NOT NULL,
	redirect_uri VARCHAR(500) NOT NULL,
	encrypted_user_token VARCHAR,
	user_token_expires_at DATETIME,
	page_id VARCHAR(100),
	page_name VARCHAR(200),
	encrypted_page_token VARCHAR,
	instagram_account_id VARCHAR(100),
	instagram_username VARCHAR(200),
	updated_by_email VARCHAR(254) NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE oauthstate (
	id INTEGER NOT NULL,
	provider VARCHAR(32) NOT NULL,
	state_hash VARCHAR(64) NOT NULL,
	requested_by_email VARCHAR(254) NOT NULL,
	expires_at DATETIME NOT NULL,
	used_at DATETIME,
	PRIMARY KEY (id)
);

CREATE TABLE oilservicecard (
	id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	source_execution_id INTEGER,
	service_name VARCHAR(120) NOT NULL,
	performed_at DATETIME NOT NULL,
	mileage_km INTEGER NOT NULL,
	next_due_km INTEGER,
	next_due_at DATETIME,
	oil_used VARCHAR(1000) NOT NULL,
	filters_used VARCHAR(2000) NOT NULL,
	customer_note VARCHAR(2000) NOT NULL,
	oil_image_path VARCHAR(500),
	oil_image_content_type VARCHAR(32),
	filter_image_path VARCHAR(500),
	filter_image_content_type VARCHAR(32),
	updated_by VARCHAR(254) NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(source_execution_id) REFERENCES maintenanceexecution (id)
);

CREATE TABLE payment (
	id INTEGER NOT NULL,
	sale_id INTEGER NOT NULL,
	method VARCHAR(32) NOT NULL,
	amount_clp INTEGER NOT NULL,
	status VARCHAR(24) NOT NULL,
	provider_reference VARCHAR(100),
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(sale_id) REFERENCES sale (id)
);

CREATE TABLE product (
	id INTEGER NOT NULL,
	sku VARCHAR(40),
	name VARCHAR(120) NOT NULL,
	category VARCHAR(80),
	unit VARCHAR(24) NOT NULL,
	stock_quantity FLOAT NOT NULL,
	minimum_quantity FLOAT NOT NULL,
	cost_clp INTEGER NOT NULL,
	price_clp INTEGER NOT NULL,
	manufacturer VARCHAR(80),
	product_type VARCHAR(40),
	oem_number VARCHAR(120),
	equivalent_codes VARCHAR(1000),
	technical_specs VARCHAR(2000),
	application_notes VARCHAR(2000),
	sae_grade VARCHAR(30),
	api_spec VARCHAR(80),
	acea_spec VARCHAR(80),
	oem_approvals VARCHAR(500),
	data_source_url VARCHAR(500),
	verification_status VARCHAR(24) NOT NULL,
	active BOOLEAN NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE purchasereceipt (
	id INTEGER NOT NULL,
	code VARCHAR(32) NOT NULL,
	supplier_id INTEGER,
	document_type VARCHAR(40) NOT NULL,
	folio VARCHAR(80),
	issue_date DATETIME,
	net_amount_clp INTEGER NOT NULL,
	tax_amount_clp INTEGER NOT NULL,
	total_amount_clp INTEGER NOT NULL,
	status VARCHAR(24) NOT NULL,
	source_format VARCHAR(12) NOT NULL,
	original_filename VARCHAR(255) NOT NULL,
	storage_path VARCHAR(500) NOT NULL,
	extraction_note VARCHAR(2000),
	cash_movement_id INTEGER,
	created_by_email VARCHAR(254),
	reviewed_by_email VARCHAR(254),
	created_at DATETIME NOT NULL,
	applied_at DATETIME,
	PRIMARY KEY (id),
	FOREIGN KEY(supplier_id) REFERENCES supplier (id),
	FOREIGN KEY(cash_movement_id) REFERENCES cashmovement (id)
);

CREATE TABLE purchasereceiptline (
	id INTEGER NOT NULL,
	purchase_receipt_id INTEGER NOT NULL,
	product_id INTEGER,
	supplier_code VARCHAR(120),
	description VARCHAR(300) NOT NULL,
	quantity FLOAT NOT NULL,
	unit_cost_clp INTEGER NOT NULL,
	line_total_clp INTEGER NOT NULL,
	match_status VARCHAR(24) NOT NULL,
	notes VARCHAR(500),
	PRIMARY KEY (id),
	FOREIGN KEY(purchase_receipt_id) REFERENCES purchasereceipt (id),
	FOREIGN KEY(product_id) REFERENCES product (id)
);

CREATE TABLE quote (
	id INTEGER NOT NULL,
	work_order_id INTEGER,
	customer_id INTEGER,
	vehicle_id INTEGER,
	prospect_name VARCHAR(160),
	prospect_phone VARCHAR(40),
	prospect_email VARCHAR(254),
	prospect_vehicle VARCHAR(180),
	description VARCHAR(250) NOT NULL,
	labor_clp INTEGER NOT NULL,
	parts_clp INTEGER NOT NULL,
	status VARCHAR(24) NOT NULL,
	customer_approved_at DATETIME,
	notes VARCHAR,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id)
);

CREATE TABLE quoteitem (
	id INTEGER NOT NULL,
	quote_id INTEGER NOT NULL,
	kind VARCHAR(16) NOT NULL,
	product_id INTEGER,
	service_id INTEGER,
	description VARCHAR(200) NOT NULL,
	quantity FLOAT NOT NULL,
	unit_price_clp INTEGER NOT NULL,
	line_total_clp INTEGER NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(quote_id) REFERENCES quote (id),
	FOREIGN KEY(product_id) REFERENCES product (id),
	FOREIGN KEY(service_id) REFERENCES service (id)
);

CREATE TABLE quoterequest (
	id INTEGER NOT NULL,
	customer_id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	description VARCHAR(2000) NOT NULL,
	status VARCHAR(24) NOT NULL,
	quote_id INTEGER,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(quote_id) REFERENCES quote (id)
);

CREATE TABLE sale (
	id INTEGER NOT NULL,
	receipt_code VARCHAR(32) NOT NULL,
	customer_id INTEGER,
	vehicle_id INTEGER,
	work_order_id INTEGER,
	subtotal_clp INTEGER NOT NULL,
	discount_clp INTEGER NOT NULL,
	total_clp INTEGER NOT NULL,
	status VARCHAR(24) NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id)
);

CREATE TABLE saleitem (
	id INTEGER NOT NULL,
	sale_id INTEGER NOT NULL,
	product_id INTEGER,
	description VARCHAR(200) NOT NULL,
	quantity FLOAT NOT NULL,
	unit_price_clp INTEGER NOT NULL,
	line_total_clp INTEGER NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(sale_id) REFERENCES sale (id),
	FOREIGN KEY(product_id) REFERENCES product (id)
);

CREATE TABLE scannerreport (
	id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	work_order_id INTEGER,
	work_order_service_id INTEGER,
	filename VARCHAR(255) NOT NULL,
	storage_path VARCHAR(500) NOT NULL,
	source VARCHAR(32) NOT NULL,
	scanned_at DATETIME NOT NULL,
	mileage_km INTEGER,
	summary VARCHAR,
	PRIMARY KEY (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(work_order_service_id) REFERENCES workorderservice (id)
);

CREATE TABLE service (
	id INTEGER NOT NULL,
	code VARCHAR(40) NOT NULL,
	name VARCHAR(160) NOT NULL,
	category_id INTEGER NOT NULL,
	description VARCHAR(2000) NOT NULL,
	price_clp INTEGER NOT NULL,
	PRIMARY KEY (id),
	UNIQUE (code),
	FOREIGN KEY(category_id) REFERENCES servicecategory (id)
);

CREATE TABLE servicecategory (
	id INTEGER NOT NULL,
	name VARCHAR(80) NOT NULL,
	PRIMARY KEY (id),
	UNIQUE (name)
);

CREATE TABLE socialbrand (
	id INTEGER NOT NULL,
	name VARCHAR NOT NULL,
	tone VARCHAR NOT NULL,
	audience VARCHAR NOT NULL,
	primary_color VARCHAR NOT NULL,
	accent_color VARCHAR NOT NULL,
	call_to_action VARCHAR NOT NULL,
	contact VARCHAR NOT NULL,
	logo_base64 VARCHAR NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE socialpost (
	id INTEGER NOT NULL,
	title VARCHAR NOT NULL,
	network VARCHAR NOT NULL,
	format VARCHAR NOT NULL,
	objective VARCHAR NOT NULL,
	product_id INTEGER,
	source_name VARCHAR NOT NULL,
	brief VARCHAR NOT NULL,
	caption VARCHAR NOT NULL,
	headline VARCHAR NOT NULL,
	image_base64 VARCHAR NOT NULL,
	brand_snapshot VARCHAR NOT NULL,
	status VARCHAR NOT NULL,
	planned_at DATETIME,
	published_at DATETIME,
	created_by VARCHAR NOT NULL,
	approved_by VARCHAR,
	generation_method VARCHAR NOT NULL,
	created_at DATETIME NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(product_id) REFERENCES product (id)
);

CREATE TABLE stockmovement (
	id INTEGER NOT NULL,
	product_id INTEGER NOT NULL,
	quantity_change FLOAT NOT NULL,
	reason VARCHAR(40) NOT NULL,
	reference VARCHAR(80),
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(product_id) REFERENCES product (id)
);

CREATE TABLE supplier (
	id INTEGER NOT NULL,
	rut VARCHAR(24),
	name VARCHAR(180) NOT NULL,
	email VARCHAR(254),
	phone VARCHAR(40),
	address VARCHAR(300),
	active BOOLEAN NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE user (
	id INTEGER NOT NULL,
	email VARCHAR(254) NOT NULL,
	full_name VARCHAR(120) NOT NULL,
	password_hash VARCHAR NOT NULL,
	role VARCHAR(8) NOT NULL,
	customer_id INTEGER,
	active BOOLEAN NOT NULL,
	token_version INTEGER NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id)
);

CREATE TABLE vehicle (
	id INTEGER NOT NULL,
	customer_id INTEGER NOT NULL,
	plate VARCHAR(12) NOT NULL,
	vin VARCHAR(32),
	make VARCHAR(60) NOT NULL,
	model VARCHAR(60) NOT NULL,
	year INTEGER,
	engine VARCHAR(80),
	engine_number VARCHAR(80),
	engine_code VARCHAR(80),
	displacement_cc INTEGER,
	current_mileage_km INTEGER,
	notes VARCHAR,
	public_service_card_enabled BOOLEAN NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id)
);

CREATE TABLE vehicletechnicalentry (
	id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	"key" VARCHAR(80) NOT NULL,
	value VARCHAR NOT NULL,
	source VARCHAR NOT NULL,
	status VARCHAR NOT NULL,
	revision INTEGER NOT NULL,
	changed_by VARCHAR NOT NULL,
	identity_signature VARCHAR NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	UNIQUE (vehicle_id, "key", revision),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id)
);

CREATE TABLE whatsappbusinessconfig (
	id INTEGER NOT NULL,
	app_id VARCHAR(100),
	business_account_id VARCHAR(100) NOT NULL,
	phone_number_id VARCHAR(100) NOT NULL,
	encrypted_access_token VARCHAR NOT NULL,
	encrypted_app_secret VARCHAR NOT NULL,
	encrypted_verify_token VARCHAR NOT NULL,
	updated_by_email VARCHAR(254) NOT NULL,
	created_at DATETIME NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE workorder (
	id INTEGER NOT NULL,
	code VARCHAR(24) NOT NULL,
	customer_id INTEGER NOT NULL,
	vehicle_id INTEGER NOT NULL,
	status VARCHAR(17) NOT NULL,
	opened_at DATETIME NOT NULL,
	promised_at DATETIME,
	mileage_km INTEGER,
	reported_symptoms VARCHAR,
	initial_notes VARCHAR,
	diagnosis VARCHAR,
	technician_name VARCHAR,
	total_clp INTEGER NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(customer_id) REFERENCES customer (id),
	FOREIGN KEY(vehicle_id) REFERENCES vehicle (id)
);

CREATE TABLE workorderassignment (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	technician_user_id INTEGER NOT NULL,
	assigned_by_email VARCHAR(254),
	assigned_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(technician_user_id) REFERENCES user (id)
);

CREATE TABLE workorderevidence (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	inspection_id INTEGER,
	filename VARCHAR(255) NOT NULL,
	storage_path VARCHAR(500) NOT NULL,
	content_type VARCHAR(80) NOT NULL,
	kind VARCHAR(32) NOT NULL,
	caption VARCHAR(250),
	uploaded_by_email VARCHAR(254) NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(inspection_id) REFERENCES inspection (id)
);

CREATE TABLE workorderqualitycheck (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	fluids_checked BOOLEAN NOT NULL,
	leaks_checked BOOLEAN NOT NULL,
	fasteners_checked BOOLEAN NOT NULL,
	road_test_done BOOLEAN NOT NULL,
	technician_completed_at DATETIME,
	technician_notes VARCHAR(4000) NOT NULL,
	reviewed_by_email VARCHAR(254),
	reviewed_at DATETIME,
	result VARCHAR(24) NOT NULL,
	review_notes VARCHAR(4000) NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id)
);

CREATE TABLE workorderreception (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	fuel_level_percent INTEGER,
	visible_damage VARCHAR,
	accessories VARCHAR,
	customer_observations VARCHAR,
	terms_accepted BOOLEAN NOT NULL,
	accepted_by_name VARCHAR(120),
	accepted_at DATETIME,
	created_at DATETIME NOT NULL,
	updated_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id)
);

CREATE TABLE workorderservice (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	catalog_service_id INTEGER,
	kind VARCHAR(32) NOT NULL,
	name VARCHAR(160) NOT NULL,
	description VARCHAR(2000) NOT NULL,
	status VARCHAR(24) NOT NULL,
	assigned_user_id INTEGER,
	findings VARCHAR(4000) NOT NULL,
	created_at DATETIME NOT NULL,
	started_at DATETIME,
	completed_at DATETIME,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(catalog_service_id) REFERENCES service (id),
	FOREIGN KEY(assigned_user_id) REFERENCES user (id)
);

CREATE TABLE worksession (
	id INTEGER NOT NULL,
	work_order_id INTEGER NOT NULL,
	work_order_service_id INTEGER,
	user_id INTEGER NOT NULL,
	started_at DATETIME NOT NULL,
	ended_at DATETIME,
	paused_at DATETIME,
	paused_seconds INTEGER NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(work_order_id) REFERENCES workorder (id),
	FOREIGN KEY(work_order_service_id) REFERENCES workorderservice (id),
	FOREIGN KEY(user_id) REFERENCES user (id)
);

CREATE TABLE workshopbay (
	id INTEGER NOT NULL,
	name VARCHAR(80) NOT NULL,
	notes VARCHAR(500) NOT NULL,
	active BOOLEAN NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id)
);

CREATE INDEX ix_aiinteraction_context_id ON aiinteraction (context_id);

CREATE INDEX ix_aiinteraction_created_at ON aiinteraction (created_at);

CREATE INDEX ix_aiinteraction_requested_by_email ON aiinteraction (requested_by_email);

CREATE INDEX ix_appointment_bay_id ON appointment (bay_id);

CREATE INDEX ix_appointment_customer_id ON appointment (customer_id);

CREATE INDEX ix_appointment_google_event_id ON appointment (google_event_id);

CREATE INDEX ix_appointment_starts_at ON appointment (starts_at);

CREATE INDEX ix_appointment_technician_user_id ON appointment (technician_user_id);

CREATE INDEX ix_appointment_vehicle_id ON appointment (vehicle_id);

CREATE INDEX ix_bulkimport_kind ON bulkimport (kind);

CREATE UNIQUE INDEX ix_cashaccount_name ON cashaccount (name);

CREATE INDEX ix_cashclosure_account_id ON cashclosure (account_id);

CREATE INDEX ix_cashmovement_account_id ON cashmovement (account_id);

CREATE INDEX ix_cashmovement_customer_id ON cashmovement (customer_id);

CREATE INDEX ix_cashmovement_occurred_at ON cashmovement (occurred_at);

CREATE UNIQUE INDEX ix_cashmovement_payment_id ON cashmovement (payment_id);

CREATE INDEX ix_cashmovement_reversal_of_id ON cashmovement (reversal_of_id);

CREATE INDEX ix_cashmovement_source_id ON cashmovement (source_id);

CREATE INDEX ix_cashmovement_vehicle_id ON cashmovement (vehicle_id);

CREATE INDEX ix_cashmovement_work_order_id ON cashmovement (work_order_id);

CREATE INDEX ix_customer_archived_at ON customer (archived_at);

CREATE INDEX ix_customer_full_name ON customer (full_name);

CREATE INDEX ix_customer_rut ON customer (rut);

CREATE INDEX ix_customeraccesstoken_customer_id ON customeraccesstoken (customer_id);

CREATE INDEX ix_customeraccesstoken_expires_at ON customeraccesstoken (expires_at);

CREATE INDEX ix_customeraccesstoken_purpose ON customeraccesstoken (purpose);

CREATE UNIQUE INDEX ix_customeraccesstoken_token_hash ON customeraccesstoken (token_hash);

CREATE INDEX ix_customeraccesstoken_user_id ON customeraccesstoken (user_id);

CREATE INDEX ix_customerengagementvisit_channel ON customerengagementvisit (channel);

CREATE INDEX ix_customerengagementvisit_customer_id ON customerengagementvisit (customer_id);

CREATE INDEX ix_customerengagementvisit_vehicle_id ON customerengagementvisit (vehicle_id);

CREATE INDEX ix_customerengagementvisit_window_start ON customerengagementvisit (window_start);

CREATE INDEX ix_diagnosticfinding_dtc_code ON diagnosticfinding (dtc_code);

CREATE INDEX ix_diagnosticfinding_scanner_report_id ON diagnosticfinding (scanner_report_id);

CREATE INDEX ix_diagnosticfinding_vehicle_id ON diagnosticfinding (vehicle_id);

CREATE INDEX ix_diagnosticfinding_work_order_id ON diagnosticfinding (work_order_id);

CREATE INDEX ix_diagnosticfinding_work_order_service_id ON diagnosticfinding (work_order_service_id);

CREATE INDEX ix_externalcalendarevent_calendar_id ON externalcalendarevent (calendar_id);

CREATE INDEX ix_externalcalendarevent_event_id ON externalcalendarevent (event_id);

CREATE INDEX ix_externalcalendarevent_starts_at ON externalcalendarevent (starts_at);

CREATE INDEX ix_externalimport_external_id ON externalimport (external_id);

CREATE INDEX ix_externalimport_provider ON externalimport (provider);

CREATE INDEX ix_externalimport_scanner_report_id ON externalimport (scanner_report_id);

CREATE INDEX ix_inspection_work_order_id ON inspection (work_order_id);

CREATE INDEX ix_inspection_work_order_service_id ON inspection (work_order_service_id);

CREATE UNIQUE INDEX ix_inspectiontemplate_key ON inspectiontemplate ("key");

CREATE INDEX ix_inspectiontemplateitem_template_id ON inspectiontemplateitem (template_id);

CREATE INDEX ix_installedpart_oem_number ON installedpart (oem_number);

CREATE INDEX ix_installedpart_vehicle_id ON installedpart (vehicle_id);

CREATE INDEX ix_installedpart_work_order_id ON installedpart (work_order_id);

CREATE INDEX ix_installedpart_work_order_service_id ON installedpart (work_order_service_id);

CREATE UNIQUE INDEX ix_integrationcredential_provider ON integrationcredential (provider);

CREATE INDEX ix_inventorycountline_product_id ON inventorycountline (product_id);

CREATE INDEX ix_inventorycountline_session_id ON inventorycountline (session_id);

CREATE UNIQUE INDEX ix_inventorycountsession_code ON inventorycountsession (code);

CREATE INDEX ix_loyaltyredemption_customer_id ON loyaltyredemption (customer_id);

CREATE INDEX ix_loyaltyredemption_reward_id ON loyaltyredemption (reward_id);

CREATE INDEX ix_loyaltytransaction_customer_id ON loyaltytransaction (customer_id);

CREATE UNIQUE INDEX ix_loyaltytransaction_sale_id ON loyaltytransaction (sale_id);

CREATE INDEX ix_maintenanceexecution_plan_id ON maintenanceexecution (plan_id);

CREATE INDEX ix_maintenanceexecution_vehicle_id ON maintenanceexecution (vehicle_id);

CREATE INDEX ix_maintenanceexecution_work_order_id ON maintenanceexecution (work_order_id);

CREATE INDEX ix_maintenanceplan_vehicle_id ON maintenanceplan (vehicle_id);

CREATE INDEX ix_oauthstate_expires_at ON oauthstate (expires_at);

CREATE INDEX ix_oauthstate_provider ON oauthstate (provider);

CREATE UNIQUE INDEX ix_oauthstate_state_hash ON oauthstate (state_hash);

CREATE UNIQUE INDEX ix_oilservicecard_vehicle_id ON oilservicecard (vehicle_id);

CREATE INDEX ix_payment_provider_reference ON payment (provider_reference);

CREATE INDEX ix_payment_sale_id ON payment (sale_id);

CREATE INDEX ix_product_name ON product (name);

CREATE UNIQUE INDEX ix_product_sku ON product (sku);

CREATE INDEX ix_purchasereceipt_cash_movement_id ON purchasereceipt (cash_movement_id);

CREATE UNIQUE INDEX ix_purchasereceipt_code ON purchasereceipt (code);

CREATE INDEX ix_purchasereceipt_supplier_id ON purchasereceipt (supplier_id);

CREATE INDEX ix_purchasereceiptline_product_id ON purchasereceiptline (product_id);

CREATE INDEX ix_purchasereceiptline_purchase_receipt_id ON purchasereceiptline (purchase_receipt_id);

CREATE INDEX ix_quote_customer_id ON quote (customer_id);

CREATE INDEX ix_quote_vehicle_id ON quote (vehicle_id);

CREATE INDEX ix_quote_work_order_id ON quote (work_order_id);

CREATE INDEX ix_quoteitem_quote_id ON quoteitem (quote_id);

CREATE INDEX ix_quoterequest_customer_id ON quoterequest (customer_id);

CREATE INDEX ix_quoterequest_vehicle_id ON quoterequest (vehicle_id);

CREATE INDEX ix_sale_customer_id ON sale (customer_id);

CREATE UNIQUE INDEX ix_sale_receipt_code ON sale (receipt_code);

CREATE INDEX ix_sale_vehicle_id ON sale (vehicle_id);

CREATE INDEX ix_sale_work_order_id ON sale (work_order_id);

CREATE INDEX ix_saleitem_sale_id ON saleitem (sale_id);

CREATE INDEX ix_scannerreport_vehicle_id ON scannerreport (vehicle_id);

CREATE INDEX ix_scannerreport_work_order_id ON scannerreport (work_order_id);

CREATE INDEX ix_scannerreport_work_order_service_id ON scannerreport (work_order_service_id);

CREATE INDEX ix_service_category_id ON service (category_id);

CREATE INDEX ix_socialpost_planned_at ON socialpost (planned_at);

CREATE INDEX ix_socialpost_status ON socialpost (status);

CREATE INDEX ix_stockmovement_product_id ON stockmovement (product_id);

CREATE INDEX ix_supplier_name ON supplier (name);

CREATE UNIQUE INDEX ix_supplier_rut ON supplier (rut);

CREATE INDEX ix_user_customer_id ON user (customer_id);

CREATE UNIQUE INDEX ix_user_email ON user (email);

CREATE INDEX ix_vehicle_customer_id ON vehicle (customer_id);

CREATE INDEX ix_vehicle_engine_number ON vehicle (engine_number);

CREATE INDEX ix_vehicle_plate ON vehicle (plate);

CREATE INDEX ix_vehicle_vin ON vehicle (vin);

CREATE INDEX ix_vehicletechnicalentry_vehicle_id ON vehicletechnicalentry (vehicle_id);

CREATE UNIQUE INDEX ix_workorder_code ON workorder (code);

CREATE INDEX ix_workorder_customer_id ON workorder (customer_id);

CREATE INDEX ix_workorder_vehicle_id ON workorder (vehicle_id);

CREATE INDEX ix_workorderassignment_technician_user_id ON workorderassignment (technician_user_id);

CREATE UNIQUE INDEX ix_workorderassignment_work_order_id ON workorderassignment (work_order_id);

CREATE INDEX ix_workorderevidence_inspection_id ON workorderevidence (inspection_id);

CREATE INDEX ix_workorderevidence_work_order_id ON workorderevidence (work_order_id);

CREATE UNIQUE INDEX ix_workorderqualitycheck_work_order_id ON workorderqualitycheck (work_order_id);

CREATE UNIQUE INDEX ix_workorderreception_work_order_id ON workorderreception (work_order_id);

CREATE INDEX ix_workorderservice_kind ON workorderservice (kind);

CREATE INDEX ix_workorderservice_work_order_id ON workorderservice (work_order_id);

CREATE INDEX ix_worksession_user_id ON worksession (user_id);

CREATE INDEX ix_worksession_work_order_id ON worksession (work_order_id);

CREATE INDEX ix_worksession_work_order_service_id ON worksession (work_order_service_id);

CREATE UNIQUE INDEX ix_workshopbay_name ON workshopbay (name);

CREATE TABLE gudex_schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);

INSERT INTO gudex_schema_migrations (version) VALUES ('0001_initial_schema');
