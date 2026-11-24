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

Por ahora están MongoDB, RabbitMQ, groups-service, balances-service, activity-service y bff-gateway. Faltan mcp-server y el frontend.

groups-service arranca con los datos de ejemplo (usuarios y grupo `g-depto`, sin gastos). Mientras no exista el login, todas las peticiones al BFF son del usuario `DEV_USER_ID` (Martín).

| Qué | Dónde |
|---|---|
| GraphQL del BFF | http://localhost:3000/graphql |
| Interfaz de RabbitMQ | http://localhost:15672 (usuario `quadra`, contraseña `quadra`) |
| MongoDB | `mongodb://localhost:27017` |

Los puertos se publican solo en `127.0.0.1`, así que nadie más en tu red (por ejemplo, el wifi de la universidad) puede conectarse. Es importante porque MongoDB no tiene contraseña en desarrollo y el BFF todavía no tiene login. Las contraseñas de MongoDB llegan en la Fase 3, con un `Secret` de Kubernetes.

Las credenciales del compose son solo para desarrollo. Se pueden cambiar con un archivo `.env` en esta carpeta (no se commitea), con las variables `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `JWT_SECRET` e `INTERNAL_API_KEY`.

Para probar la conexión entre el BFF y activity-service, ver "Probar la conexión con activity-service" en el README de bff-gateway.

## Probar el flujo completo

En http://localhost:3000/graphql (GraphiQL), crear un gasto:

```graphql
mutation {
  createExpense(input: {
    groupId: "g-depto", description: "Gas", amount: 18000, paidBy: "u-sofia", source: MANUAL,
    shares: [
      { userId: "u-martin", amount: 4500 }, { userId: "u-camila", amount: 4500 },
      { userId: "u-sofia", amount: 4500 }, { userId: "u-diego", amount: 4500 }
    ]
  }) { id description }
}
```

Y ver que se refleja en los tres servicios con una sola consulta:

```graphql
{
  group(id: "g-depto") {
    name
    expenses { description amount paidBy { name } }  # groups-service
    balances { member { name } net }                 # balances-service
    settlementPlan { from { name } to { name } amount }
    activity(limit: 5) { text }                      # activity-service
  }
}
```

Prueba de resiliencia: `docker compose stop balances-service`, crear otro gasto (se guarda y aparece en el feed; el mensaje espera en la cola `balances.events` de la interfaz de RabbitMQ), y `docker compose start balances-service`: los saldos se ponen al día solos.

Para empezar de cero: `docker compose down -v && docker compose up -d --build --wait`.
