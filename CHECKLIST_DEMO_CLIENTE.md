# Checklist de recorrido final — demo Burger King CR (workforce-ai-os)

Uso: hacé este recorrido en el navegador, en orden, como si fueras el cliente viendo la demo por primera vez. Marcá cada punto. Cualquier cosa que falle o se vea rara, anotala en la columna de notas y avisame para corregirla antes de la reunión.

Corré primero `bash verificacion_final_demo.sh` (backend) — este checklist es el complemento visual/funcional que el script no puede ver.

## 0. Antes de arrancar

- [ ] `docker compose ps` — los 4 contenedores (`api`, `frontend`, `postgres`, `redis`) están `Up`/`healthy`.
- [ ] La URL del túnel Cloudflare carga sin error de certificado ni "sitio no disponible".
- [ ] Login con el usuario admin del tenant Burger King funciona sin error.
- [ ] Cambiar el idioma a inglés (`/en`) y volver a español — la interfaz no queda a medio traducir.

## 1. Dashboard (Inicio)

- [ ] Los 7 KPIs cargan con números reales (no en blanco, no "undefined").
- [ ] El KPI de "onboarding incompleto" coincide con lo que se ve luego en Empleados/Centro de Onboarding.
- [ ] Los gráficos (Recharts) se ven completos, sin overflow ni etiquetas cortadas.

## 2. Empleados

- [ ] Buscar por nombre funciona.
- [ ] Filtro por sucursal funciona.
- [ ] Badge de "onboarding incompleto" aparece en los empleados que corresponde.
- [ ] Botón "Verificar onboarding" redirige al Centro de Onboarding (ya no muestra el toast genérico).
- [ ] Crear un empleado nuevo — aparece en la lista sin recargar manualmente, con toast de éxito.
- [ ] Editar un empleado (incluye cuenta bancaria) — guarda y refleja el cambio al instante.
- [ ] Crear un contrato — elegir idioma (ES/EN), descargar el PDF, confirmar que sale en un solo idioma y con los datos correctos.
- [ ] El panel de edición muestra la advertencia de onboarding faltante cuando corresponde.

## 3. Centro de Onboarding

- [ ] Banner de riesgo de nómina aparece solo si hay período abierto + empleados sin cuenta bancaria.
- [ ] Las 3 tarjetas resumen (cuenta bancaria / contrato / biométrico) filtran la tabla al hacer clic.
- [ ] Gráfico de gaps por sucursal se ve correctamente.
- [ ] Botón "Resolver" de un gap de cuenta bancaria o contrato → manda a Empleados con el empleado resaltado.
- [ ] Botón "Resolver" de un gap **solo** de biométrico → manda a Dispositivos con el empleado pre-seleccionado en el checklist.

## 4. Dispositivos + Biométrico

- [ ] CRUD de dispositivos (crear, editar, desactivar/reactivar) funciona con toast.
- [ ] Sección de biométrico: por defecto muestra solo empleados **pendientes**, con contador y barra de progreso.
- [ ] Filtro de sucursal en la sección biométrica funciona.
- [ ] Toggle "ver todos los empleados" muestra la lista completa con check verde en los ya enrolados.
- [ ] Enrolar a un empleado (consentimiento + dispositivo + tipo) — el empleado desaparece del checklist pendiente automáticamente.

## 5. Feature Flags

- [ ] Buscar por nombre funciona.
- [ ] Descripción de cada flag se muestra debajo del nombre.
- [ ] Toggle de un flag por tenant funciona con toast.

## 6. Marcación

- [ ] Filtro de sucursal y búsqueda funcionan.
- [ ] Crear una marcación con verificación real (facial/tarjeta) — no pide motivo, no genera excepción.
- [ ] Crear una marcación manual — pide motivo obligatorio, muestra el aviso de "queda pendiente de aprobación", y el toast dice "pendiente" en vez de "ok".
- [ ] Botón "Corregir marca" en un registro → lleva a Excepciones con empleado y marcación pre-cargados.

## 7. Excepciones

- [ ] Búsqueda y filtro de sucursal funcionan.
- [ ] La excepción automática creada por una marcación manual aparece en la cola, pendiente.
- [ ] Aprobar/rechazar una excepción funciona con toast y autorefresh.

## 8. Confianza Operativa™

- [ ] Búsqueda y filtro de sucursal funcionan.
- [ ] Las 3 reglas heurísticas (biométrico faltante, mismo tipo consecutivo, viaje imposible) se ven representadas si hay datos de prueba que las disparen.
- [ ] Resolver una señal funciona con toast.

## 9. Turnos

- [ ] CRUD de plantillas de turno (crear, editar, desactivar) funciona.
- [ ] Asignación master-detail con filtro de sucursal y detección de choque de horario funciona.
- [ ] Endpoint de cobertura se ve reflejado visualmente si aplica.

## 10. Sucursales

- [ ] CRUD completo funciona.
- [ ] Ver empleados por sucursal funciona.

## 11. Usuarios y Roles (RBAC)

- [ ] CRUD de roles funciona.
- [ ] Loguearse con un usuario de rol limitado (no admin) y confirmar que los botones/pantallas sin permiso están ocultos, no solo deshabilitados.

## 12. Nómina — catálogos

- [ ] Cada catálogo (feriados, tramos de renta, créditos, config. vacaciones/aguinaldo/cesantía, plan de cuentas, config. archivo bancario, config. anomalías) carga y permite editar.
- [ ] Ningún catálogo muestra un valor "quemado" sin posibilidad de editarlo desde la UI.

## 13. Nómina — flujo operativo

- [ ] Calendario de períodos: crear/generar un período nuevo.
- [ ] Horas extra: un caso pendiente bloquea el bruto del empleado hasta aprobarse.
- [ ] Vacaciones: solicitar y aprobar, ver el balance actualizado.
- [ ] Aguinaldo: se calcula sin pedir aprobación.
- [ ] Cesantía: crear una terminación de prueba y ver el cálculo.
- [ ] Asientos contables: generar y exportar CSV.
- [ ] Archivo bancario: generar y descargar el TXT, confirmar formato (columnas por tab, sin encabezado).

## 14. Payroll Run (orquestación)

- [ ] La pantalla de Corridas muestra las 7 etapas sin em-dash roto ni status sin traducir.
- [ ] Avanzar un período de prueba por las transiciones (draft → validado → calculado) sin saltarse pasos.
- [ ] El motor de anomalías (6 reglas) muestra alguna señal si hay datos de prueba que la disparen.
- [ ] Intentar avanzar con catálogos faltantes — el sistema bloquea con el mensaje correcto, no con un error genérico.

## 15. Reportes

- [ ] Reporte de horas trabajadas: exportar PDF y Excel, confirmar que el drilldown por sucursal/empleado funciona y el logo aparece en todas las páginas.

## 16. Responsive / PWA

- [ ] Achicar la ventana o probar en un celular real — el sidebar y las tablas no se rompen.
- [ ] Confirmar que la app se puede "instalar" como PWA (ícono, manifest) si eso ya está habilitado.

---

**Antes de la reunión con el cliente:** si algo de esta lista falla, avisame con el nombre exacto de la sección y qué viste — lo corrijo antes de la demo, no durante.
