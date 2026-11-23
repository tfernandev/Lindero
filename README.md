# Lindero

Juego corto de mesa con hexágonos (estilo Catan) hecho en **Godot 4.6**.  
Tablero 3D, recursos, caminos, puestos y granjas. Pensado para PC y celular.

## Requisitos

1. Una PC con Windows, macOS o Linux.
2. **Godot 4.6** (versión *Standard*, no hace falta la .NET).

Descargá Godot desde: https://godotengine.org/download  
Elegí **4.6.x** y el build **Standard**.

No necesitás saber programar ni haber hecho juegos antes.

## Cómo abrirlo (paso a paso)

1. Descargá o cloná este repositorio.
   - En GitHub: botón verde **Code** → **Download ZIP** → descomprimí.
   - O en una terminal:
     ```bash
     git clone https://github.com/tfernandev/Lindero.git
     ```
2. Abrí **Godot**.
3. En el Project Manager, tocá **Import** / **Importar**.
4. Buscá la carpeta del proyecto y elegí el archivo `project.godot`.
5. Tocá **Import & Edit**.
6. La primera vez Godot va a importar modelos y texturas: puede tardar unos minutos. Esperá a que termine.
7. Tocá el botón ▶ (Play) arriba a la derecha, o F5.
8. Debería abrir el menú del juego. Desde ahí podés empezar una partida.

Escena inicial: `scenes/menu.tscn`.

## Controles rápidos en partida

- Tocá el tablero para colocar puestos y caminos (los puntos y rayas blancas marcan lo válido).
- **Tirar dados** cuando sea tu turno.
- Menú (arriba a la izquierda): Calma (menos animación), nueva partida, volver al inicio.

## Si algo falla

| Problema | Qué probar |
|---|---|
| Godot dice que la versión no coincide | Usá Godot **4.6** (no 4.3 ni 4.5). |
| La primera apertura tarda mucho | Normal: está importando los `.glb` 3D. |
| El tablero se ve vacío o rosa | Esperá a que termine la importación y volvé a darle Play. |
| No aparece el proyecto | Asegurate de importar la carpeta que **contiene** `project.godot`. |

## Notas técnicas (opcional)

- Motor: Godot 4.6 Mobile.
- Lógica de partida: `scripts/match.gd`.
- Tablero 3D: `scripts/table_board.gd` + modelos en `models/`.
- UI: `scripts/match_hud.gd`, `scenes/main.tscn`.

El repo incluye los modelos 3D necesarios para jugar (~250 MB). La primera clonación/descarga puede pesar bastante.
