# Inventario de API para la migración a Cloudflare

Generado desde `backend/app.main:app.openapi()` con `python cloudflare/scripts/generate_api_inventory.py`.
Este reporte es una línea base del contrato HTTP; las reglas de negocio, efectos laterales, límites de cliente, formatos de archivo e idempotencia requieren revisión del código y validación funcional antes de portar cada grupo.

Operaciones HTTP documentadas: **235** en **184** paths OpenAPI.

## Conteo por dominio o etiqueta

| Dominio | Operaciones |
|---|---:|
| Administración | 3 |
| Agenda | 5 |
| Asistente | 2 |
| Autenticación | 6 |
| caja central | 8 |
| Caja y ventas | 6 |
| carga masiva | 4 |
| Catálogo e inventario | 6 |
| Clientes | 8 |
| compras y proveedores | 10 |
| Contenido y redes | 12 |
| Cotizaciones | 10 |
| inspecciones | 11 |
| Integraciones | 27 |
| Mantenciones | 6 |
| mantenciones | 1 |
| operación de taller | 9 |
| Otros | 9 |
| Portal cliente | 19 |
| portal de inspecciones | 4 |
| Respaldos | 1 |
| servicios | 8 |
| Taller e inspecciones | 1 |
| Taller y diagnóstico | 4 |
| Taller y órdenes | 17 |
| tarjeta pública | 7 |
| toma de inventario | 8 |
| trabajos y repuestos | 8 |
| Usuarios | 6 |
| Vehículos | 9 |

## Rutas

| Método | Ruta | Dominio | Resumen | Acceso observado | Operation ID | Código origen |
|---|---|---|---|---|---|---|
| GET | `/api/v1/dashboard` | Administración | Workshop Dashboard | admin | `workshop_dashboard_api_v1_dashboard_get` | `backend/app/main.py:916` |
| GET | `/api/v1/team/mechanics` | Administración | List Mechanics | admin | `list_mechanics_api_v1_team_mechanics_get` | `backend/app/main.py:1028` |
| GET | `/api/v1/team/productivity` | Administración | Mechanic Productivity | admin | `mechanic_productivity_api_v1_team_productivity_get` | `backend/app/main.py:1037` |
| GET | `/api/v1/appointments` | Agenda | List Appointments | JWT middleware; permiso fino por confirmar | `list_appointments_api_v1_appointments_get` | `backend/app/main.py:1772` |
| POST | `/api/v1/appointments` | Agenda | Create Appointment | admin | `create_appointment_api_v1_appointments_post` | `backend/app/main.py:1749` |
| PATCH | `/api/v1/appointments/{appointment_id}` | Agenda | Update Appointment | admin | `update_appointment_api_v1_appointments__appointment_id__patch` | `backend/app/main.py:1825` |
| DELETE | `/api/v1/appointments/{appointment_id}` | Agenda | Cancel Appointment | admin | `cancel_appointment_api_v1_appointments__appointment_id__delete` | `backend/app/main.py:1854` |
| PATCH | `/api/v1/appointments/{appointment_id}/status` | Agenda | Update Appointment Status | admin | `update_appointment_status_api_v1_appointments__appointment_id__status_patch` | `backend/app/main.py:1803` |
| POST | `/api/v1/assistant/interactions/{interaction_id}/confirm` | Asistente | Confirm Assistant Action | JWT middleware; permiso fino por confirmar | `confirm_assistant_action_api_v1_assistant_interactions__interaction_id__confirm_post` | pendiente |
| POST | `/api/v1/assistant/query` | Asistente | Assistant Query | JWT middleware; permiso fino por confirmar | `assistant_query_api_v1_assistant_query_post` | pendiente |
| POST | `/auth/customer/activate` | Autenticación | Activate Customer Access | público (revisar bypass/hook) | `activate_customer_access_auth_customer_activate_post` | `backend/app/main.py:474` |
| POST | `/auth/customer/password-reset` | Autenticación | Request Customer Password Reset | público (revisar bypass/hook) | `request_customer_password_reset_auth_customer_password_reset_post` | `backend/app/main.py:496` |
| POST | `/auth/customer/password-reset/confirm` | Autenticación | Confirm Customer Password Reset | público (revisar bypass/hook) | `confirm_customer_password_reset_auth_customer_password_reset_confirm_post` | `backend/app/main.py:506` |
| GET | `/auth/google/callback` | Autenticación | Google Callback | público (revisar bypass/hook) | `google_callback_auth_google_callback_get` | pendiente |
| GET | `/auth/meta/callback` | Autenticación | Meta Callback | público (revisar bypass/hook) | `meta_callback_auth_meta_callback_get` | pendiente |
| POST | `/auth/token` | Autenticación | Login | público (revisar bypass/hook) | `login_auth_token_post` | `backend/app/main.py:206` |
| GET | `/api/v1/cash/accounts` | caja central | List Cash Accounts | JWT middleware; permiso fino por confirmar | `list_cash_accounts_api_v1_cash_accounts_get` | pendiente |
| POST | `/api/v1/cash/accounts` | caja central | Create Cash Account | JWT middleware; permiso fino por confirmar | `create_cash_account_api_v1_cash_accounts_post` | pendiente |
| POST | `/api/v1/cash/closures/open` | caja central | Open Cash Closure | JWT middleware; permiso fino por confirmar | `open_cash_closure_api_v1_cash_closures_open_post` | pendiente |
| POST | `/api/v1/cash/closures/{closure_id}/close` | caja central | Close Cash Closure | JWT middleware; permiso fino por confirmar | `close_cash_closure_api_v1_cash_closures__closure_id__close_post` | pendiente |
| POST | `/api/v1/cash/expenses` | caja central | Create Cash Expense | JWT middleware; permiso fino por confirmar | `create_cash_expense_api_v1_cash_expenses_post` | pendiente |
| GET | `/api/v1/cash/movements` | caja central | List Cash Movements | JWT middleware; permiso fino por confirmar | `list_cash_movements_api_v1_cash_movements_get` | pendiente |
| GET | `/api/v1/cash/summary` | caja central | Cash Summary | JWT middleware; permiso fino por confirmar | `cash_summary_api_v1_cash_summary_get` | pendiente |
| POST | `/api/v1/cash/transfers` | caja central | Create Cash Transfer | JWT middleware; permiso fino por confirmar | `create_cash_transfer_api_v1_cash_transfers_post` | pendiente |
| GET | `/api/v1/sales` | Caja y ventas | List Sales | admin | `list_sales_api_v1_sales_get` | `backend/app/main.py:2361` |
| POST | `/api/v1/sales` | Caja y ventas | Create Sale | admin | `create_sale_api_v1_sales_post` | `backend/app/main.py:2252` |
| POST | `/api/v1/sales/{sale_id}/mercado-pago/cancel` | Caja y ventas | Cancel Mercado Pago Checkout | admin | `cancel_mercado_pago_checkout_api_v1_sales__sale_id__mercado_pago_cancel_post` | `backend/app/main.py:2562` |
| POST | `/api/v1/sales/{sale_id}/mercado-pago/checkout` | Caja y ventas | Create Mercado Pago Checkout | admin | `create_mercado_pago_checkout_api_v1_sales__sale_id__mercado_pago_checkout_post` | `backend/app/main.py:2401` |
| POST | `/api/v1/sales/{sale_id}/payments` | Caja y ventas | Record Payment | admin | `record_payment_api_v1_sales__sale_id__payments_post` | `backend/app/main.py:2318` |
| GET | `/api/v1/sales/{sale_id}/receipt.pdf` | Caja y ventas | Download Sale Receipt | admin | `download_sale_receipt_api_v1_sales__sale_id__receipt_pdf_get` | `backend/app/main.py:2385` |
| GET | `/api/v1/bulk/{kind}/export` | carga masiva | Export | JWT middleware; permiso fino por confirmar | `export_api_v1_bulk__kind__export_get` | pendiente |
| GET | `/api/v1/bulk/{kind}/history` | carga masiva | History | JWT middleware; permiso fino por confirmar | `history_api_v1_bulk__kind__history_get` | pendiente |
| POST | `/api/v1/bulk/{kind}/preview` | carga masiva | Preview | JWT middleware; permiso fino por confirmar | `preview_api_v1_bulk__kind__preview_post` | pendiente |
| POST | `/api/v1/bulk/{kind}/{import_id}/confirm` | carga masiva | Confirm | JWT middleware; permiso fino por confirmar | `confirm_api_v1_bulk__kind___import_id__confirm_post` | pendiente |
| GET | `/api/v1/products` | Catálogo e inventario | List Products | JWT middleware; permiso fino por confirmar | `list_products_api_v1_products_get` | `backend/app/main.py:2041` |
| POST | `/api/v1/products` | Catálogo e inventario | Create Product | admin | `create_product_api_v1_products_post` | `backend/app/main.py:2027` |
| PATCH | `/api/v1/products/{product_id}` | Catálogo e inventario | Update Product | admin | `update_product_api_v1_products__product_id__patch` | `backend/app/main.py:2051` |
| DELETE | `/api/v1/products/{product_id}` | Catálogo e inventario | Archive Product | admin | `archive_product_api_v1_products__product_id__delete` | `backend/app/main.py:2066` |
| GET | `/api/v1/products/{product_id}/stock-movements` | Catálogo e inventario | List Stock Movements | JWT middleware; permiso fino por confirmar | `list_stock_movements_api_v1_products__product_id__stock_movements_get` | `backend/app/main.py:2076` |
| POST | `/api/v1/products/{product_id}/stock-movements` | Catálogo e inventario | Adjust Stock | admin | `adjust_stock_api_v1_products__product_id__stock_movements_post` | `backend/app/main.py:2104` |
| GET | `/api/v1/customers` | Clientes | List Customers | admin/mecánico | `list_customers_api_v1_customers_get` | `backend/app/main.py:606` |
| POST | `/api/v1/customers` | Clientes | Create Customer | admin | `create_customer_api_v1_customers_post` | `backend/app/main.py:593` |
| GET | `/api/v1/customers/engagement` | Clientes | Customer Engagement | admin/mecánico | `customer_engagement_api_v1_customers_engagement_get` | `backend/app/main.py:619` |
| POST | `/api/v1/customers/with-portal-access` | Clientes | Create Customer With Portal Access | admin | `create_customer_with_portal_access_api_v1_customers_with_portal_access_post` | `backend/app/main.py:385` |
| PATCH | `/api/v1/customers/{customer_id}` | Clientes | Update Customer | admin | `update_customer_api_v1_customers__customer_id__patch` | `backend/app/main.py:644` |
| DELETE | `/api/v1/customers/{customer_id}` | Clientes | Delete Customer | admin | `delete_customer_api_v1_customers__customer_id__delete` | `backend/app/main.py:691` |
| POST | `/api/v1/customers/{customer_id}/portal-access/invitation` | Clientes | Resend Customer Invitation | admin | `resend_customer_invitation_api_v1_customers__customer_id__portal_access_invitation_post` | `backend/app/main.py:452` |
| POST | `/api/v1/customers/{customer_id}/portal-access/password` | Clientes | Set Customer Portal Password | admin | `set_customer_portal_password_api_v1_customers__customer_id__portal_access_password_post` | `backend/app/main.py:419` |
| GET | `/api/v1/purchases` | compras y proveedores | List Purchases | JWT middleware; permiso fino por confirmar | `list_purchases_api_v1_purchases_get` | pendiente |
| POST | `/api/v1/purchases/import` | compras y proveedores | Import Purchase Document | JWT middleware; permiso fino por confirmar | `import_purchase_document_api_v1_purchases_import_post` | pendiente |
| GET | `/api/v1/purchases/{receipt_id}` | compras y proveedores | Purchase Detail | JWT middleware; permiso fino por confirmar | `purchase_detail_api_v1_purchases__receipt_id__get` | pendiente |
| POST | `/api/v1/purchases/{receipt_id}/apply` | compras y proveedores | Apply Purchase | JWT middleware; permiso fino por confirmar | `apply_purchase_api_v1_purchases__receipt_id__apply_post` | pendiente |
| GET | `/api/v1/purchases/{receipt_id}/file` | compras y proveedores | Purchase File | JWT middleware; permiso fino por confirmar | `purchase_file_api_v1_purchases__receipt_id__file_get` | pendiente |
| PATCH | `/api/v1/purchases/{receipt_id}/lines/{line_id}` | compras y proveedores | Update Purchase Line | JWT middleware; permiso fino por confirmar | `update_purchase_line_api_v1_purchases__receipt_id__lines__line_id__patch` | pendiente |
| POST | `/api/v1/purchases/{receipt_id}/lines/{line_id}/create-product` | compras y proveedores | Create Product From Purchase Line | JWT middleware; permiso fino por confirmar | `create_product_from_purchase_line_api_v1_purchases__receipt_id__lines__line_id__create_product_post` | pendiente |
| GET | `/api/v1/suppliers` | compras y proveedores | List Suppliers | JWT middleware; permiso fino por confirmar | `list_suppliers_api_v1_suppliers_get` | pendiente |
| POST | `/api/v1/suppliers` | compras y proveedores | Create Supplier | JWT middleware; permiso fino por confirmar | `create_supplier_api_v1_suppliers_post` | pendiente |
| PATCH | `/api/v1/suppliers/{supplier_id}` | compras y proveedores | Update Supplier | JWT middleware; permiso fino por confirmar | `update_supplier_api_v1_suppliers__supplier_id__patch` | pendiente |
| GET | `/api/v1/social/accounts` | Contenido y redes | Accounts | JWT middleware; permiso fino por confirmar | `accounts_api_v1_social_accounts_get` | pendiente |
| GET | `/api/v1/social/brand` | Contenido y redes | Read Brand | JWT middleware; permiso fino por confirmar | `read_brand_api_v1_social_brand_get` | pendiente |
| PUT | `/api/v1/social/brand` | Contenido y redes | Update Brand | JWT middleware; permiso fino por confirmar | `update_brand_api_v1_social_brand_put` | pendiente |
| GET | `/api/v1/social/posts` | Contenido y redes | List Posts | JWT middleware; permiso fino por confirmar | `list_posts_api_v1_social_posts_get` | pendiente |
| POST | `/api/v1/social/posts` | Contenido y redes | Create Post | JWT middleware; permiso fino por confirmar | `create_post_api_v1_social_posts_post` | pendiente |
| GET | `/api/v1/social/posts/{post_id}` | Contenido y redes | Read Post | JWT middleware; permiso fino por confirmar | `read_post_api_v1_social_posts__post_id__get` | pendiente |
| PUT | `/api/v1/social/posts/{post_id}` | Contenido y redes | Update Post | JWT middleware; permiso fino por confirmar | `update_post_api_v1_social_posts__post_id__put` | pendiente |
| DELETE | `/api/v1/social/posts/{post_id}` | Contenido y redes | Delete Post | JWT middleware; permiso fino por confirmar | `delete_post_api_v1_social_posts__post_id__delete` | pendiente |
| GET | `/api/v1/social/posts/{post_id}/export` | Contenido y redes | Export | JWT middleware; permiso fino por confirmar | `export_api_v1_social_posts__post_id__export_get` | pendiente |
| POST | `/api/v1/social/posts/{post_id}/generate` | Contenido y redes | Generate | JWT middleware; permiso fino por confirmar | `generate_api_v1_social_posts__post_id__generate_post` | pendiente |
| GET | `/api/v1/social/posts/{post_id}/preview.png` | Contenido y redes | Preview | JWT middleware; permiso fino por confirmar | `preview_api_v1_social_posts__post_id__preview_png_get` | pendiente |
| POST | `/api/v1/social/posts/{post_id}/status` | Contenido y redes | Change Status | JWT middleware; permiso fino por confirmar | `change_status_api_v1_social_posts__post_id__status_post` | pendiente |
| GET | `/api/v1/quote-requests` | Cotizaciones | List Quote Requests | admin | `list_quote_requests_api_v1_quote_requests_get` | `backend/app/main.py:1444` |
| POST | `/api/v1/quote-requests/{request_id}/draft` | Cotizaciones | Convert Quote Request | admin | `convert_quote_request_api_v1_quote_requests__request_id__draft_post` | `backend/app/main.py:1452` |
| GET | `/api/v1/quotes` | Cotizaciones | List Quotes | admin | `list_quotes_api_v1_quotes_get` | `backend/app/main.py:1411` |
| POST | `/api/v1/quotes` | Cotizaciones | Create Standalone Quote | admin | `create_standalone_quote_api_v1_quotes_post` | `backend/app/main.py:1399` |
| PUT | `/api/v1/quotes/{quote_id}` | Cotizaciones | Update Quote | admin | `update_quote_api_v1_quotes__quote_id__put` | `backend/app/main.py:1468` |
| DELETE | `/api/v1/quotes/{quote_id}` | Cotizaciones | Delete Quote | admin | `delete_quote_api_v1_quotes__quote_id__delete` | `backend/app/main.py:1514` |
| POST | `/api/v1/quotes/{quote_id}/customer-approval` | Cotizaciones | Approve Quote | admin | `approve_quote_api_v1_quotes__quote_id__customer_approval_post` | `backend/app/main.py:1527` |
| POST | `/api/v1/quotes/{quote_id}/email` | Cotizaciones | Email Quote | admin | `email_quote_api_v1_quotes__quote_id__email_post` | `backend/app/main.py:1491` |
| GET | `/api/v1/quotes/{quote_id}/pdf` | Cotizaciones | Download Quote | admin | `download_quote_api_v1_quotes__quote_id__pdf_get` | `backend/app/main.py:1478` |
| POST | `/api/v1/quotes/{quote_id}/publish` | Cotizaciones | Publish Quote | admin | `publish_quote_api_v1_quotes__quote_id__publish_post` | `backend/app/main.py:1546` |
| GET | `/api/v1/evidence/{evidence_id}/file` | inspecciones | Download Evidence | JWT middleware; permiso fino por confirmar | `download_evidence_api_v1_evidence__evidence_id__file_get` | pendiente |
| GET | `/api/v1/inspection-templates` | inspecciones | List Templates | JWT middleware; permiso fino por confirmar | `list_templates_api_v1_inspection_templates_get` | pendiente |
| POST | `/api/v1/inspection-templates` | inspecciones | Create Template | JWT middleware; permiso fino por confirmar | `create_template_api_v1_inspection_templates_post` | pendiente |
| PATCH | `/api/v1/inspections/{inspection_id}` | inspecciones | Update Inspection | JWT middleware; permiso fino por confirmar | `update_inspection_api_v1_inspections__inspection_id__patch` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/evidence` | inspecciones | List Evidence | JWT middleware; permiso fino por confirmar | `list_evidence_api_v1_work_orders__order_id__evidence_get` | pendiente |
| POST | `/api/v1/work-orders/{order_id}/evidence` | inspecciones | Upload Evidence | JWT middleware; permiso fino por confirmar | `upload_evidence_api_v1_work_orders__order_id__evidence_post` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/inspection-report` | inspecciones | Inspection Report | JWT middleware; permiso fino por confirmar | `inspection_report_api_v1_work_orders__order_id__inspection_report_get` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/inspection-report.pdf` | inspecciones | Download Inspection Report | JWT middleware; permiso fino por confirmar | `download_inspection_report_api_v1_work_orders__order_id__inspection_report_pdf_get` | pendiente |
| POST | `/api/v1/work-orders/{order_id}/inspection-templates/{template_id}/apply` | inspecciones | Apply Template | JWT middleware; permiso fino por confirmar | `apply_template_api_v1_work_orders__order_id__inspection_templates__template_id__apply_post` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/reception` | inspecciones | Get Reception | JWT middleware; permiso fino por confirmar | `get_reception_api_v1_work_orders__order_id__reception_get` | pendiente |
| PUT | `/api/v1/work-orders/{order_id}/reception` | inspecciones | Save Reception | JWT middleware; permiso fino por confirmar | `save_reception_api_v1_work_orders__order_id__reception_put` | pendiente |
| PUT | `/api/v1/integrations/ai/model` | Integraciones | Update Ai Model | JWT middleware; permiso fino por confirmar | `update_ai_model_api_v1_integrations_ai_model_put` | pendiente |
| GET | `/api/v1/integrations/ai/models` | Integraciones | List Ai Models | JWT middleware; permiso fino por confirmar | `list_ai_models_api_v1_integrations_ai_models_get` | pendiente |
| DELETE | `/api/v1/integrations/google` | Integraciones | Disconnect Google | JWT middleware; permiso fino por confirmar | `disconnect_google_api_v1_integrations_google_delete` | pendiente |
| POST | `/api/v1/integrations/google/authorize` | Integraciones | Authorize Google | JWT middleware; permiso fino por confirmar | `authorize_google_api_v1_integrations_google_authorize_post` | pendiente |
| PUT | `/api/v1/integrations/google/calendar-selection` | Integraciones | Select Google Calendar | JWT middleware; permiso fino por confirmar | `select_google_calendar_api_v1_integrations_google_calendar_selection_put` | pendiente |
| POST | `/api/v1/integrations/google/calendar/import` | Integraciones | Import Google Calendar | JWT middleware; permiso fino por confirmar | `import_google_calendar_api_v1_integrations_google_calendar_import_post` | pendiente |
| POST | `/api/v1/integrations/google/calendar/sync-pending` | Integraciones | Sync Pending Calendar | JWT middleware; permiso fino por confirmar | `sync_pending_calendar_api_v1_integrations_google_calendar_sync_pending_post` | pendiente |
| GET | `/api/v1/integrations/google/calendars` | Integraciones | List Google Calendars | JWT middleware; permiso fino por confirmar | `list_google_calendars_api_v1_integrations_google_calendars_get` | pendiente |
| GET | `/api/v1/integrations/google/config` | Integraciones | Get Google Settings | JWT middleware; permiso fino por confirmar | `get_google_settings_api_v1_integrations_google_config_get` | pendiente |
| PUT | `/api/v1/integrations/google/config` | Integraciones | Save Google Settings | JWT middleware; permiso fino por confirmar | `save_google_settings_api_v1_integrations_google_config_put` | pendiente |
| GET | `/api/v1/integrations/google/scanner-candidates` | Integraciones | Scanner Candidates | JWT middleware; permiso fino por confirmar | `scanner_candidates_api_v1_integrations_google_scanner_candidates_get` | pendiente |
| POST | `/api/v1/integrations/google/scanner-import` | Integraciones | Import Scanner Report | JWT middleware; permiso fino por confirmar | `import_scanner_report_api_v1_integrations_google_scanner_import_post` | pendiente |
| POST | `/api/v1/integrations/mercado-pago/webhook` | Integraciones | Mercado Pago Webhook | JWT middleware; permiso fino por confirmar | `mercado_pago_webhook_api_v1_integrations_mercado_pago_webhook_post` | `backend/app/main.py:2470` |
| DELETE | `/api/v1/integrations/meta` | Integraciones | Disconnect Meta | JWT middleware; permiso fino por confirmar | `disconnect_meta_api_v1_integrations_meta_delete` | pendiente |
| POST | `/api/v1/integrations/meta/authorize` | Integraciones | Authorize Meta | JWT middleware; permiso fino por confirmar | `authorize_meta_api_v1_integrations_meta_authorize_post` | pendiente |
| GET | `/api/v1/integrations/meta/config` | Integraciones | Get Meta Settings | JWT middleware; permiso fino por confirmar | `get_meta_settings_api_v1_integrations_meta_config_get` | pendiente |
| PUT | `/api/v1/integrations/meta/config` | Integraciones | Save Meta Settings | JWT middleware; permiso fino por confirmar | `save_meta_settings_api_v1_integrations_meta_config_put` | pendiente |
| GET | `/api/v1/integrations/meta/pages` | Integraciones | Meta Pages | JWT middleware; permiso fino por confirmar | `meta_pages_api_v1_integrations_meta_pages_get` | pendiente |
| POST | `/api/v1/integrations/meta/select-page` | Integraciones | Select Meta Page | JWT middleware; permiso fino por confirmar | `select_meta_page_api_v1_integrations_meta_select_page_post` | pendiente |
| GET | `/api/v1/integrations/status` | Integraciones | Integration Status | JWT middleware; permiso fino por confirmar | `integration_status_api_v1_integrations_status_get` | pendiente |
| POST | `/api/v1/integrations/whatsapp/baileys/connect` | Integraciones | Connect Baileys | JWT middleware; permiso fino por confirmar | `connect_baileys_api_v1_integrations_whatsapp_baileys_connect_post` | pendiente |
| POST | `/api/v1/integrations/whatsapp/baileys/reset` | Integraciones | Reset Baileys | JWT middleware; permiso fino por confirmar | `reset_baileys_api_v1_integrations_whatsapp_baileys_reset_post` | pendiente |
| GET | `/api/v1/integrations/whatsapp/baileys/status` | Integraciones | Baileys Status | JWT middleware; permiso fino por confirmar | `baileys_status_api_v1_integrations_whatsapp_baileys_status_get` | pendiente |
| POST | `/api/v1/integrations/whatsapp/baileys/test-message` | Integraciones | Send Baileys Test Message | JWT middleware; permiso fino por confirmar | `send_baileys_test_message_api_v1_integrations_whatsapp_baileys_test_message_post` | pendiente |
| GET | `/api/v1/integrations/whatsapp/business` | Integraciones | Whatsapp Business Config | JWT middleware; permiso fino por confirmar | `whatsapp_business_config_api_v1_integrations_whatsapp_business_get` | pendiente |
| PUT | `/api/v1/integrations/whatsapp/business` | Integraciones | Save Whatsapp Business Config | JWT middleware; permiso fino por confirmar | `save_whatsapp_business_config_api_v1_integrations_whatsapp_business_put` | pendiente |
| DELETE | `/api/v1/integrations/whatsapp/business` | Integraciones | Delete Whatsapp Business Config | JWT middleware; permiso fino por confirmar | `delete_whatsapp_business_config_api_v1_integrations_whatsapp_business_delete` | pendiente |
| GET | `/api/v1/maintenance-plans` | Mantenciones | List Maintenance Plans | admin/mecánico | `list_maintenance_plans_api_v1_maintenance_plans_get` | `backend/app/main.py:855` |
| POST | `/api/v1/maintenance-plans` | Mantenciones | Create Maintenance Plan | admin | `create_maintenance_plan_api_v1_maintenance_plans_post` | `backend/app/main.py:843` |
| GET | `/api/v1/maintenance-plans/due` | Mantenciones | Due Maintenance Plans | admin/mecánico | `due_maintenance_plans_api_v1_maintenance_plans_due_get` | `backend/app/main.py:881` |
| PATCH | `/api/v1/maintenance-plans/{plan_id}` | Mantenciones | Update Maintenance Plan | admin | `update_maintenance_plan_api_v1_maintenance_plans__plan_id__patch` | `backend/app/main.py:860` |
| DELETE | `/api/v1/maintenance-plans/{plan_id}` | Mantenciones | Archive Maintenance Plan | admin | `archive_maintenance_plan_api_v1_maintenance_plans__plan_id__delete` | `backend/app/main.py:872` |
| POST | `/api/v1/maintenance-plans/{plan_id}/complete` | Mantenciones | Complete Maintenance Plan | admin | `complete_maintenance_plan_api_v1_maintenance_plans__plan_id__complete_post` | `backend/app/main.py:902` |
| POST | `/api/v1/maintenance-plans/{plan_id}/executions` | mantenciones | Complete | JWT middleware; permiso fino por confirmar | `complete_api_v1_maintenance_plans__plan_id__executions_post` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/diagnostics` | operación de taller | List Diagnostics | JWT middleware; permiso fino por confirmar | `list_diagnostics_api_v1_work_orders__order_id__diagnostics_get` | pendiente |
| POST | `/api/v1/work-orders/{order_id}/diagnostics` | operación de taller | Create Diagnostic | JWT middleware; permiso fino por confirmar | `create_diagnostic_api_v1_work_orders__order_id__diagnostics_post` | pendiente |
| PATCH | `/api/v1/work-orders/{order_id}/diagnostics/{finding_id}` | operación de taller | Update Diagnostic | JWT middleware; permiso fino por confirmar | `update_diagnostic_api_v1_work_orders__order_id__diagnostics__finding_id__patch` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/quality-check` | operación de taller | Get Quality Check | JWT middleware; permiso fino por confirmar | `get_quality_check_api_v1_work_orders__order_id__quality_check_get` | pendiente |
| PUT | `/api/v1/work-orders/{order_id}/quality-check` | operación de taller | Save Quality Check | JWT middleware; permiso fino por confirmar | `save_quality_check_api_v1_work_orders__order_id__quality_check_put` | pendiente |
| POST | `/api/v1/work-orders/{order_id}/quality-check/review` | operación de taller | Review Quality Check | JWT middleware; permiso fino por confirmar | `review_quality_check_api_v1_work_orders__order_id__quality_check_review_post` | pendiente |
| GET | `/api/v1/workshop/bays` | operación de taller | List Workshop Bays | JWT middleware; permiso fino por confirmar | `list_workshop_bays_api_v1_workshop_bays_get` | pendiente |
| POST | `/api/v1/workshop/bays` | operación de taller | Create Workshop Bay | JWT middleware; permiso fino por confirmar | `create_workshop_bay_api_v1_workshop_bays_post` | pendiente |
| PATCH | `/api/v1/workshop/bays/{bay_id}` | operación de taller | Update Workshop Bay | JWT middleware; permiso fino por confirmar | `update_workshop_bay_api_v1_workshop_bays__bay_id__patch` | pendiente |
| GET | `/api/v1/loyalty/customers/{customer_id}` | Otros | Loyalty Balance | admin | `loyalty_balance_api_v1_loyalty_customers__customer_id__get` | `backend/app/main.py:1697` |
| GET | `/api/v1/loyalty/redemptions` | Otros | List Loyalty Redemptions | admin | `list_loyalty_redemptions_api_v1_loyalty_redemptions_get` | `backend/app/main.py:1628` |
| POST | `/api/v1/loyalty/redemptions/{redemption_id}/{status}` | Otros | Update Loyalty Redemption | admin | `update_loyalty_redemption_api_v1_loyalty_redemptions__redemption_id___status__post` | `backend/app/main.py:1634` |
| POST | `/api/v1/loyalty/rewards` | Otros | Create Loyalty Reward | admin | `create_loyalty_reward_api_v1_loyalty_rewards_post` | `backend/app/main.py:1621` |
| GET | `/api/v1/marketing/campaigns` | Otros | List Marketing Campaigns | admin | `list_marketing_campaigns_api_v1_marketing_campaigns_get` | `backend/app/main.py:1658` |
| POST | `/api/v1/marketing/campaigns` | Otros | Create Marketing Campaign | admin | `create_marketing_campaign_api_v1_marketing_campaigns_post` | `backend/app/main.py:1663` |
| PUT | `/api/v1/marketing/campaigns/{campaign_id}` | Otros | Edit Marketing Campaign | admin | `edit_marketing_campaign_api_v1_marketing_campaigns__campaign_id__put` | `backend/app/main.py:1672` |
| POST | `/api/v1/marketing/campaigns/{campaign_id}/status` | Otros | Update Campaign Status | admin | `update_campaign_status_api_v1_marketing_campaigns__campaign_id__status_post` | `backend/app/main.py:1686` |
| GET | `/health` | Otros | Health | público (revisar bypass/hook) | `health_health_get` | `backend/app/main.py:527` |
| GET | `/api/v1/portal/appointments` | Portal cliente | Customer Appointments | cliente (portal; validar alcance por cliente) | `customer_appointments_api_v1_portal_appointments_get` | `backend/app/main.py:1888` |
| POST | `/api/v1/portal/appointments` | Portal cliente | Request Appointment | cliente (portal; validar alcance por cliente) | `request_appointment_api_v1_portal_appointments_post` | `backend/app/main.py:1867` |
| PATCH | `/api/v1/portal/appointments/{appointment_id}` | Portal cliente | Update Customer Appointment | cliente (portal; validar alcance por cliente) | `update_customer_appointment_api_v1_portal_appointments__appointment_id__patch` | `backend/app/main.py:1902` |
| DELETE | `/api/v1/portal/appointments/{appointment_id}` | Portal cliente | Cancel Customer Appointment | cliente (portal; validar alcance por cliente) | `cancel_customer_appointment_api_v1_portal_appointments__appointment_id__delete` | `backend/app/main.py:1934` |
| POST | `/api/v1/portal/assistant/query` | Portal cliente | Customer Assistant Query | cliente (portal; validar alcance por cliente) | `customer_assistant_query_api_v1_portal_assistant_query_post` | pendiente |
| GET | `/api/v1/portal/documents` | Portal cliente | Customer Documents | cliente (portal; validar alcance por cliente) | `customer_documents_api_v1_portal_documents_get` | `backend/app/main.py:1956` |
| GET | `/api/v1/portal/loyalty` | Portal cliente | Customer Loyalty | cliente (portal; validar alcance por cliente) | `customer_loyalty_api_v1_portal_loyalty_get` | `backend/app/main.py:1591` |
| GET | `/api/v1/portal/maintenance-plans` | Portal cliente | Customer Maintenance Plans | cliente (portal; validar alcance por cliente) | `customer_maintenance_plans_api_v1_portal_maintenance_plans_get` | `backend/app/main.py:1894` |
| GET | `/api/v1/portal/notifications` | Portal cliente | Customer Notifications | cliente (portal; validar alcance por cliente) | `customer_notifications_api_v1_portal_notifications_get` | `backend/app/main.py:1968` |
| GET | `/api/v1/portal/profile` | Portal cliente | Customer Portal Profile | cliente (portal; validar alcance por cliente) | `customer_portal_profile_api_v1_portal_profile_get` | `backend/app/main.py:1567` |
| GET | `/api/v1/portal/quote-requests` | Portal cliente | List Portal Quote Requests | cliente (portal; validar alcance por cliente) | `list_portal_quote_requests_api_v1_portal_quote_requests_get` | `backend/app/main.py:1438` |
| POST | `/api/v1/portal/quote-requests` | Portal cliente | Create Portal Quote Request | cliente (portal; validar alcance por cliente) | `create_portal_quote_request_api_v1_portal_quote_requests_post` | `backend/app/main.py:1427` |
| GET | `/api/v1/portal/quotes` | Portal cliente | Customer Portal Quotes | cliente (portal; validar alcance por cliente) | `customer_portal_quotes_api_v1_portal_quotes_get` | `backend/app/main.py:1950` |
| POST | `/api/v1/portal/quotes/{quote_id}/approval` | Portal cliente | Customer Portal Approve Quote | cliente (portal; validar alcance por cliente) | `customer_portal_approve_quote_api_v1_portal_quotes__quote_id__approval_post` | `backend/app/main.py:2006` |
| GET | `/api/v1/portal/quotes/{quote_id}/pdf` | Portal cliente | Customer Quote Pdf | cliente (portal; validar alcance por cliente) | `customer_quote_pdf_api_v1_portal_quotes__quote_id__pdf_get` | `backend/app/main.py:1989` |
| GET | `/api/v1/portal/rewards` | Portal cliente | Customer Rewards | cliente (portal; validar alcance por cliente) | `customer_rewards_api_v1_portal_rewards_get` | `backend/app/main.py:1599` |
| POST | `/api/v1/portal/rewards/{reward_id}/redeem` | Portal cliente | Redeem Reward | cliente (portal; validar alcance por cliente) | `redeem_reward_api_v1_portal_rewards__reward_id__redeem_post` | `backend/app/main.py:1604` |
| GET | `/api/v1/portal/vehicles/{vehicle_id}/history` | Portal cliente | Customer Vehicle History | cliente (portal; validar alcance por cliente) | `customer_vehicle_history_api_v1_portal_vehicles__vehicle_id__history_get` | `backend/app/main.py:957` |
| GET | `/api/v1/portal/work-orders` | Portal cliente | Customer Portal Work Orders | cliente (portal; validar alcance por cliente) | `customer_portal_work_orders_api_v1_portal_work_orders_get` | `backend/app/main.py:2000` |
| GET | `/api/v1/portal/evidence/{evidence_id}/file` | portal de inspecciones | Portal Download Evidence | cliente (portal; validar alcance por cliente) | `portal_download_evidence_api_v1_portal_evidence__evidence_id__file_get` | pendiente |
| GET | `/api/v1/portal/scanner-reports/{report_id}/file` | portal de inspecciones | Portal Download Scanner Report | cliente (portal; validar alcance por cliente) | `portal_download_scanner_report_api_v1_portal_scanner_reports__report_id__file_get` | pendiente |
| GET | `/api/v1/portal/work-orders/{order_id}/inspection-report` | portal de inspecciones | Portal Inspection Report | cliente (portal; validar alcance por cliente) | `portal_inspection_report_api_v1_portal_work_orders__order_id__inspection_report_get` | pendiente |
| GET | `/api/v1/portal/work-orders/{order_id}/inspection-report.pdf` | portal de inspecciones | Portal Download Inspection Report | cliente (portal; validar alcance por cliente) | `portal_download_inspection_report_api_v1_portal_work_orders__order_id__inspection_report_pdf_get` | pendiente |
| GET | `/api/v1/backups/customers-vehicles` | Respaldos | Backup Customers Vehicles | admin | `backup_customers_vehicles_api_v1_backups_customers_vehicles_get` | `backend/app/main.py:539` |
| GET | `/api/v1/service-categories` | servicios | Categories | JWT middleware; permiso fino por confirmar | `categories_api_v1_service_categories_get` | pendiente |
| POST | `/api/v1/service-categories` | servicios | Create Category | JWT middleware; permiso fino por confirmar | `create_category_api_v1_service_categories_post` | pendiente |
| PUT | `/api/v1/service-categories/{category_id}` | servicios | Edit Category | JWT middleware; permiso fino por confirmar | `edit_category_api_v1_service_categories__category_id__put` | pendiente |
| DELETE | `/api/v1/service-categories/{category_id}` | servicios | Delete Category | JWT middleware; permiso fino por confirmar | `delete_category_api_v1_service_categories__category_id__delete` | pendiente |
| GET | `/api/v1/services` | servicios | Services | JWT middleware; permiso fino por confirmar | `services_api_v1_services_get` | pendiente |
| POST | `/api/v1/services` | servicios | Create Service | JWT middleware; permiso fino por confirmar | `create_service_api_v1_services_post` | pendiente |
| PUT | `/api/v1/services/{service_id}` | servicios | Edit Service | JWT middleware; permiso fino por confirmar | `edit_service_api_v1_services__service_id__put` | pendiente |
| DELETE | `/api/v1/services/{service_id}` | servicios | Delete Service | JWT middleware; permiso fino por confirmar | `delete_service_api_v1_services__service_id__delete` | pendiente |
| DELETE | `/api/v1/inspections/{inspection_id}` | Taller e inspecciones | Delete Inspection | admin/mecánico | `delete_inspection_api_v1_inspections__inspection_id__delete` | `backend/app/main.py:1291` |
| POST | `/api/v1/scanner-reports` | Taller y diagnóstico | Upload Scanner Report | admin/mecánico | `upload_scanner_report_api_v1_scanner_reports_post` | `backend/app/main.py:2119` |
| DELETE | `/api/v1/scanner-reports/{report_id}` | Taller y diagnóstico | Delete Scanner Report | admin | `delete_scanner_report_api_v1_scanner_reports__report_id__delete` | `backend/app/main.py:2205` |
| POST | `/api/v1/scanner-reports/{report_id}/email` | Taller y diagnóstico | Email Scanner Report | admin | `email_scanner_report_api_v1_scanner_reports__report_id__email_post` | `backend/app/main.py:2184` |
| GET | `/api/v1/scanner-reports/{report_id}/file` | Taller y diagnóstico | Download Scanner Report | JWT middleware; permiso fino por confirmar | `download_scanner_report_api_v1_scanner_reports__report_id__file_get` | `backend/app/main.py:2176` |
| GET | `/api/v1/work-orders` | Taller y órdenes | List Work Orders | admin/mecánico | `list_work_orders_api_v1_work_orders_get` | `backend/app/main.py:1015` |
| POST | `/api/v1/work-orders` | Taller y órdenes | Create Work Order | admin | `create_work_order_api_v1_work_orders_post` | `backend/app/main.py:988` |
| GET | `/api/v1/work-orders/mine` | Taller y órdenes | My Work Orders | admin/mecánico | `my_work_orders_api_v1_work_orders_mine_get` | `backend/app/main.py:1066` |
| GET | `/api/v1/work-orders/{order_id}` | Taller y órdenes | Get Work Order | admin/mecánico | `get_work_order_api_v1_work_orders__order_id__get` | `backend/app/main.py:1112` |
| PATCH | `/api/v1/work-orders/{order_id}` | Taller y órdenes | Update Work Order | admin/mecánico | `update_work_order_api_v1_work_orders__order_id__patch` | `backend/app/main.py:1120` |
| DELETE | `/api/v1/work-orders/{order_id}` | Taller y órdenes | Delete Work Order | admin | `delete_work_order_api_v1_work_orders__order_id__delete` | `backend/app/main.py:1240` |
| PUT | `/api/v1/work-orders/{order_id}/assignment` | Taller y órdenes | Assign Work Order | admin | `assign_work_order_api_v1_work_orders__order_id__assignment_put` | `backend/app/main.py:1084` |
| GET | `/api/v1/work-orders/{order_id}/inspections` | Taller y órdenes | List Inspections | admin/mecánico | `list_inspections_api_v1_work_orders__order_id__inspections_get` | `backend/app/main.py:1284` |
| POST | `/api/v1/work-orders/{order_id}/inspections` | Taller y órdenes | Add Inspection | admin/mecánico | `add_inspection_api_v1_work_orders__order_id__inspections_post` | `backend/app/main.py:1270` |
| GET | `/api/v1/work-orders/{order_id}/payment-draft` | Taller y órdenes | Work Order Payment Draft | admin | `work_order_payment_draft_api_v1_work_orders__order_id__payment_draft_get` | `backend/app/main.py:2215` |
| GET | `/api/v1/work-orders/{order_id}/quotes` | Taller y órdenes | List Work Order Quotes | JWT middleware; permiso fino por confirmar | `list_work_order_quotes_api_v1_work_orders__order_id__quotes_get` | `backend/app/main.py:1404` |
| POST | `/api/v1/work-orders/{order_id}/quotes` | Taller y órdenes | Create Quote | admin | `create_quote_api_v1_work_orders__order_id__quotes_post` | `backend/app/main.py:1301` |
| GET | `/api/v1/work-orders/{order_id}/work-sessions` | Taller y órdenes | List Work Sessions | admin/mecánico | `list_work_sessions_api_v1_work_orders__order_id__work_sessions_get` | `backend/app/main.py:1167` |
| POST | `/api/v1/work-orders/{order_id}/work-sessions/start` | Taller y órdenes | Start Work Session | admin/mecánico | `start_work_session_api_v1_work_orders__order_id__work_sessions_start_post` | `backend/app/main.py:1180` |
| POST | `/api/v1/work-sessions/{session_id}/pause` | Taller y órdenes | Pause Work Session | admin/mecánico | `pause_work_session_api_v1_work_sessions__session_id__pause_post` | `backend/app/main.py:1197` |
| POST | `/api/v1/work-sessions/{session_id}/resume` | Taller y órdenes | Resume Work Session | admin/mecánico | `resume_work_session_api_v1_work_sessions__session_id__resume_post` | `backend/app/main.py:1211` |
| POST | `/api/v1/work-sessions/{session_id}/stop` | Taller y órdenes | Stop Work Session | admin/mecánico | `stop_work_session_api_v1_work_sessions__session_id__stop_post` | `backend/app/main.py:1224` |
| GET | `/api/v1/portal/vehicles/{vehicle_id}/oil-card/images/{kind}` | tarjeta pública | Portal Oil Card Image | cliente (portal; validar alcance por cliente) | `portal_oil_card_image_api_v1_portal_vehicles__vehicle_id__oil_card_images__kind__get` | pendiente |
| PUT | `/api/v1/vehicles/{vehicle_id}/oil-card` | tarjeta pública | Save Oil Card | JWT middleware; permiso fino por confirmar | `save_oil_card_api_v1_vehicles__vehicle_id__oil_card_put` | pendiente |
| GET | `/api/v1/vehicles/{vehicle_id}/oil-card/images/{kind}` | tarjeta pública | Staff Oil Card Image | JWT middleware; permiso fino por confirmar | `staff_oil_card_image_api_v1_vehicles__vehicle_id__oil_card_images__kind__get` | pendiente |
| POST | `/api/v1/vehicles/{vehicle_id}/oil-card/images/{kind}` | tarjeta pública | Upload Oil Card Image | JWT middleware; permiso fino por confirmar | `upload_oil_card_image_api_v1_vehicles__vehicle_id__oil_card_images__kind__post` | pendiente |
| DELETE | `/api/v1/vehicles/{vehicle_id}/oil-card/images/{kind}` | tarjeta pública | Remove Oil Card Image | JWT middleware; permiso fino por confirmar | `remove_oil_card_image_api_v1_vehicles__vehicle_id__oil_card_images__kind__delete` | pendiente |
| GET | `/tarjeta-aceite` | tarjeta pública | Public Oil Card | público (revisar bypass/hook) | `public_oil_card_tarjeta_aceite_get` | pendiente |
| GET | `/tarjeta-aceite/imagen/{vehicle_id}/{kind}` | tarjeta pública | Public Oil Card Image | público (revisar bypass/hook) | `public_oil_card_image_tarjeta_aceite_imagen__vehicle_id___kind__get` | pendiente |
| GET | `/api/v1/inventory-counts` | toma de inventario | List Inventory Counts | JWT middleware; permiso fino por confirmar | `list_inventory_counts_api_v1_inventory_counts_get` | pendiente |
| POST | `/api/v1/inventory-counts` | toma de inventario | Create Inventory Count | JWT middleware; permiso fino por confirmar | `create_inventory_count_api_v1_inventory_counts_post` | pendiente |
| GET | `/api/v1/inventory-counts/{session_id}` | toma de inventario | Inventory Count Detail | JWT middleware; permiso fino por confirmar | `inventory_count_detail_api_v1_inventory_counts__session_id__get` | pendiente |
| POST | `/api/v1/inventory-counts/{session_id}/apply` | toma de inventario | Apply Inventory Count | JWT middleware; permiso fino por confirmar | `apply_inventory_count_api_v1_inventory_counts__session_id__apply_post` | pendiente |
| PUT | `/api/v1/inventory-counts/{session_id}/lines` | toma de inventario | Save Inventory Count Line | JWT middleware; permiso fino por confirmar | `save_inventory_count_line_api_v1_inventory_counts__session_id__lines_put` | pendiente |
| GET | `/api/v1/inventory-counts/{session_id}/lookup` | toma de inventario | Lookup Barcode | JWT middleware; permiso fino por confirmar | `lookup_barcode_api_v1_inventory_counts__session_id__lookup_get` | pendiente |
| POST | `/api/v1/inventory-counts/{session_id}/missing-product` | toma de inventario | Create Missing Product For Count | JWT middleware; permiso fino por confirmar | `create_missing_product_for_count_api_v1_inventory_counts__session_id__missing_product_post` | pendiente |
| POST | `/api/v1/inventory-counts/{session_id}/submit` | toma de inventario | Submit Inventory Count | JWT middleware; permiso fino por confirmar | `submit_inventory_count_api_v1_inventory_counts__session_id__submit_post` | pendiente |
| GET | `/api/v1/parts/usage` | trabajos y repuestos | Part Usage | JWT middleware; permiso fino por confirmar | `part_usage_api_v1_parts_usage_get` | pendiente |
| GET | `/api/v1/work-order-service-kinds` | trabajos y repuestos | Service Kinds | JWT middleware; permiso fino por confirmar | `service_kinds_api_v1_work_order_service_kinds_get` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/parts` | trabajos y repuestos | List Order Parts | JWT middleware; permiso fino por confirmar | `list_order_parts_api_v1_work_orders__order_id__parts_get` | pendiente |
| POST | `/api/v1/work-orders/{order_id}/parts` | trabajos y repuestos | Add Part | JWT middleware; permiso fino por confirmar | `add_part_api_v1_work_orders__order_id__parts_post` | pendiente |
| PATCH | `/api/v1/work-orders/{order_id}/parts/{part_id}` | trabajos y repuestos | Update Part | JWT middleware; permiso fino por confirmar | `update_part_api_v1_work_orders__order_id__parts__part_id__patch` | pendiente |
| GET | `/api/v1/work-orders/{order_id}/services` | trabajos y repuestos | List Services | JWT middleware; permiso fino por confirmar | `list_services_api_v1_work_orders__order_id__services_get` | pendiente |
| POST | `/api/v1/work-orders/{order_id}/services` | trabajos y repuestos | Add Service | JWT middleware; permiso fino por confirmar | `add_service_api_v1_work_orders__order_id__services_post` | pendiente |
| PATCH | `/api/v1/work-orders/{order_id}/services/{service_id}` | trabajos y repuestos | Update Service | JWT middleware; permiso fino por confirmar | `update_service_api_v1_work_orders__order_id__services__service_id__patch` | pendiente |
| POST | `/api/v1/account/password` | Usuarios | Change Password | JWT middleware; permiso fino por confirmar | `change_password_api_v1_account_password_post` | `backend/app/main.py:223` |
| GET | `/api/v1/users` | Usuarios | List Users | admin | `list_users_api_v1_users_get` | `backend/app/main.py:260` |
| POST | `/api/v1/users` | Usuarios | Create User | admin | `create_user_api_v1_users_post` | `backend/app/main.py:239` |
| PATCH | `/api/v1/users/{user_id}` | Usuarios | Update User | admin | `update_user_api_v1_users__user_id__patch` | `backend/app/main.py:268` |
| DELETE | `/api/v1/users/{user_id}` | Usuarios | Deactivate User | admin | `deactivate_user_api_v1_users__user_id__delete` | `backend/app/main.py:313` |
| POST | `/api/v1/users/{user_id}/password` | Usuarios | Reset Staff Password | admin | `reset_staff_password_api_v1_users__user_id__password_post` | `backend/app/main.py:298` |
| GET | `/api/v1/vehicles` | Vehículos | List Vehicles | admin/mecánico | `list_vehicles_api_v1_vehicles_get` | `backend/app/main.py:739` |
| POST | `/api/v1/vehicles` | Vehículos | Create Vehicle | admin | `create_vehicle_api_v1_vehicles_post` | `backend/app/main.py:713` |
| PATCH | `/api/v1/vehicles/{vehicle_id}` | Vehículos | Update Vehicle | admin | `update_vehicle_api_v1_vehicles__vehicle_id__patch` | `backend/app/main.py:752` |
| DELETE | `/api/v1/vehicles/{vehicle_id}` | Vehículos | Delete Vehicle | admin | `delete_vehicle_api_v1_vehicles__vehicle_id__delete` | `backend/app/main.py:776` |
| GET | `/api/v1/vehicles/{vehicle_id}/history` | Vehículos | Vehicle History | admin/mecánico | `vehicle_history_api_v1_vehicles__vehicle_id__history_get` | `backend/app/main.py:835` |
| GET | `/api/v1/vehicles/{vehicle_id}/scanner-reports` | Vehículos | List Scanner Reports | JWT middleware; permiso fino por confirmar | `list_scanner_reports_api_v1_vehicles__vehicle_id__scanner_reports_get` | `backend/app/main.py:2169` |
| POST | `/api/v1/vehicles/{vehicle_id}/technical-assistant` | Vehículos | Assistant | JWT middleware; permiso fino por confirmar | `assistant_api_v1_vehicles__vehicle_id__technical_assistant_post` | pendiente |
| GET | `/api/v1/vehicles/{vehicle_id}/technical-history` | Vehículos | History | JWT middleware; permiso fino por confirmar | `history_api_v1_vehicles__vehicle_id__technical_history_get` | pendiente |
| PUT | `/api/v1/vehicles/{vehicle_id}/technical/{key}` | Vehículos | Save | JWT middleware; permiso fino por confirmar | `save_api_v1_vehicles__vehicle_id__technical__key__put` | pendiente |

## Siguientes verificaciones del inventario

- Asociar cada ruta a pantalla/flujo Flutter y prioridad operativa.
- Confirmar rol efectivo, autorización por propietario/cliente y excepciones de webhook.
- Marcar efectos externos, archivos, tareas diferidas, transacciones e idempotencia.
- Acordar cuerpos/respuestas y errores con el Worker antes de cada corte por dominio.
