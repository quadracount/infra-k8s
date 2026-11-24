# infra-k8s

Infraestructura de QuadraCount:

- `docker-compose.yml`: desarrollo local.
- `k8s/`: manifiestos de Kubernetes (namespace `quadracount`). El pipeline los valida con `kubeconform`.

## Desarrollo local con Docker Compose

Todos los repos tienen que estar clonados en la misma carpeta, porque el compose construye las imágenes desde `../<repo>`:

```
quadracount/
├── activity-service/
├── bff-gateway/
├── infra-k8s/        <- desde aquí se ejecuta
└── ...
```

```bash
docker compose up -d --build --wait
docker compose ps
docker compose logs -f activity-service
docker compose down          # agregar -v para borrar también los datos de MongoDB
```

Por ahora están MongoDB, RabbitMQ, activity-service y bff-gateway. Los demás servicios se agregan a medida que se implementan.

| Qué | Dónde |
|---|---|
| GraphQL del BFF | http://localhost:3000/graphql |
| Interfaz de RabbitMQ | http://localhost:15672 (usuario `quadra`, contraseña `quadra`) |
| MongoDB | `mongodb://localhost:27017` |

Las credenciales del compose son solo para desarrollo. Se pueden cambiar con un archivo `.env` en esta carpeta (no se commitea), con las variables `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `JWT_SECRET` e `INTERNAL_API_KEY`.

Para probar la conexión entre el BFF y activity-service, ver "Probar la conexión con activity-service" en el README de bff-gateway.
