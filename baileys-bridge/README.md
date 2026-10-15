# Bridge Baileys de Gudex (solo pruebas)

Este servicio es una alternativa **no oficial**, limitada a pruebas controladas de conexión y mensajería. No reemplaza la API oficial de WhatsApp Business, no procesa campañas, no recibe conversaciones de clientes y no debe exponerse a Internet.

## Variables requeridas

- `BAILEYS_BRIDGE_TOKEN`: secreto aleatorio compartido únicamente con el backend Gudex.
- `BAILEYS_TEST_ENABLED=true`: habilita el emparejamiento y los mensajes de prueba.
- `BAILEYS_TEST_RECIPIENTS=569XXXXXXXX,56...`: lista cerrada de números internacionales que pueden recibir pruebas.
- `BAILEYS_AUTH_DIR=/data/baileys-auth`: directorio de una unidad persistente. No guardar ni copiar este directorio al repositorio.

## Railway

1. Cree un servicio separado desde `baileys-bridge` y asígnele un volumen persistente montado en `/data`.
2. Configure las variables anteriores; use el mismo `BAILEYS_BRIDGE_TOKEN` en el servicio backend.
3. En el backend Gudex agregue `BAILEYS_SERVICE_URL=http://<nombre-servicio>.railway.internal:3000`, el mismo token y `BAILEYS_TEST_ENABLED=true`.
4. Abra **Integraciones > WhatsApp de pruebas**, inicie el emparejamiento y escanee el QR desde un teléfono de prueba.

El estado y QR se sirven al bridge solo con token interno, y Gudex los entrega exclusivamente a administradores autenticados.
