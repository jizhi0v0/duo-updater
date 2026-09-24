# Novedades de DuoUpdater

Esta es la traducción al español del archivo CHANGELOG.md. La versión en inglés es la autoridad en caso de discrepancias. Los números de versión no incluidos aquí se mostrarán automáticamente en inglés en la ventana de Novedades.

## 0.4.3

**Las betas y versiones candidatas de Xcode ahora se actualizan con un clic.** Inicia sesión una vez con tu cuenta de Apple Developer en Ajustes → Xcode, y DuoUpdater descarga e instala las nuevas betas y RC como cualquier otra actualización. Antes, solo podía avisarte de que había salido una nueva.

**Instala cualquier versión de Xcode junto a las que ya tienes.** Ajustes → Xcode muestra todas las versiones de Xcode, agrupadas por versión, con el grupo de tu macOS ya abierto. «Instalar» pone la que elijas en Aplicaciones como una copia propia —por ejemplo, Xcode-26.6.app— sin reemplazar nada; o guarda solo el archivo (.xip). Si has iniciado sesión, se incluye la propia lista de Apple, así que las nuevas versiones aparecen en minutos.

**Tu sesión de Apple Developer se mantiene sola.** Apple cierra una sesión de desarrollador tras unas ocho horas; DuoUpdater ahora obtiene una nueva en segundo plano —sin ventana y sin contraseña— mientras Apple siga reconociendo este Mac. Puedes desactivarlo en Ajustes → Xcode.

**Las nuevas versiones de Xcode aparecen antes.** Los días laborables, en el horario en que Apple suele publicar, DuoUpdater busca un nuevo Xcode cada cinco minutos.

**Algunas apps vuelven a funcionar después de que sus desarrolladores cambiaran cosas.** CapCut beta y Superconductor nightly vuelven a encontrarse e instalarse, y Superconductor conserva su identidad de app actual. VLC 3.0.24 y JetBrains Air vuelven a mostrar sus notas de versión.

## 0.4.2

**Qoder CN IDE ya es compatible.** La edición para China continental del IDE de Qoder tiene comprobación de actualizaciones, instalación con un clic y sus notas de versión en la ventana. Qoder CN, la app de escritorio, ahora también muestra sus notas de versión.

**Qoder IDE ya no cambia de opinión sobre cuál es la última versión.** Qoder distribuye las actualizaciones de forma gradual, y DuoUpdater ahora pregunta de la misma manera que tu copia del IDE, así que recibe siempre la misma respuesta. Antes, la versión ofrecida podía alternar entre dos versiones, y una instalación con un clic podía quedarse a medias porque la respuesta cambiaba.

**Las apps con Sparkle que descargaron una actualización que ya quedó atrasada se pueden volver a actualizar.** Si una app que se actualiza sola mediante Sparkle descargó una versión y después salió otra más nueva, DuoUpdater ahora elimina la descarga antigua e instala la última. Antes, «Actualizar» repetía que instalar ahora se desharía, y la fila nunca cambiaba.

**`duo install` te avisa cuando la última versión ya está esperando.** Si el actualizador propio de una app ya descargó la última versión, ahora lo dice y sugiere cerrar la app o ejecutar `duo restart`. Antes decía, por error, que la app solo se podía comprobar y no instalar.

## 0.4.1

**搜狗输入法 ya se actualiza con un clic.** DuoUpdater lo aplica igual que el propio método de entrada se actualiza —el paquete instalado se queda donde está— y antes copia tu diccionario y tus ajustes, así una reversión también los recupera.

**Las copias de seguridad en otro disco ya conservan el diccionario y los ajustes de un método de entrada.** Antes solo se trasladaba la app al disco de copias, así que revertir un método de entrada desde allí dejaba atrás los datos de la versión más nueva.

**Se acabaron las actualizaciones que nunca se pueden instalar.** JetBrains Air ahora muestra la versión que Toolbox ofrece de verdad. Una app de la App Store que quedó con su nombre antiguo después de que su desarrollador la renombrara ahora te dice qué copia actualiza la App Store, en lugar de ofrecer una actualización que solo reinstala la otra copia.

**Las notas de versión de más apps se ven con formato.** Las apps que publican sus notas en Markdown ahora reciben la misma lista nativa que las demás. Antes, las notas aparecían como texto plano.

## 0.4.0

**Reabrir ya no compite con el instalador de la propia app.** Cuando una app ha descargado su propia actualización y su copia de reversión va en un disco externo, ese traslado ahora espera a que el instalador termine. Antes se hacía durante los pocos segundos que macOS le da para trabajar.

## 0.3.99

**Las copias de seguridad para revertir ya pueden vivir en otro disco.** Una copia de seguridad es una copia entera de una app, y en el disco de arranque se acumulan. Ajustes → Copias de seguridad muestra los discos conectados con el espacio libre de cada uno, traslada las copias que ya tienes y escribe las nuevas ahí en segundo plano: si el disco no está conectado, tendrás una espera, no un punto de reversión que falta. `duo backups` ha ganado `disks`, `sync`, `verify` y `probe`.

**千问输入法 ya es compatible.** DuoUpdater te avisa cuando sale una nueva versión y actualiza el método de entrada igual que él se actualiza a sí mismo.

**Las notas de la versión ya no se quedan ancladas en la versión anterior.** Cuando un desarrollador publica una actualización unos minutos antes de que su página de cambios la mencione, las notas antiguas quedaban archivadas bajo la versión nueva y ahí se quedaban para siempre. CleanShot X llevaba desde el primer día mostrando las notas de 5.0 bajo 5.0.1.

**Borrar una copia de seguridad ahora libera el espacio que dice liberar.** Las copias tomadas por versiones anteriores de DuoUpdater se escribían de una forma que macOS se niega a borrar, así que Limpiar dejaba casi toda la copia en el disco y aun así la contaba como recuperada.

**Limpiar se abre al instante.** Antes volvía a medir desde cero cada copia de seguridad guardada cada vez que lo pulsabas.

**WorkBuddy vuelve a mostrar su versión más reciente.** Su servicio de actualización responde con el siguiente paso de una cadena de actualizaciones en lugar de con la compilación más reciente, así que las cuatro ediciones de WorkBuddy se quedaron dos versiones atrás.

**Por dentro.** Una app que nunca declaró qué binario ejecuta —Muse, de Meta, entre ellas— ahora muestra igualmente sus frameworks y su SDK.

## 0.3.98

**Las actualizaciones que termina Reabrir ahora se pueden revertir.** Cuando una app ya ha descargado su propia actualización y pulsas Reabrir, DuoUpdater guarda primero la versión actual, así que la actualización aparece en Reversión como cualquier otra. Antes solo se podían deshacer las actualizaciones que instalaba el propio DuoUpdater.

**Mira qué cambió una actualización dentro de una app.** Para cualquier app con una versión anterior guardada, el workbench tiene ahora una vista Diferencias del paquete junto a Notas de la versión: firma y permisos, macOS mínimo, ítems en segundo plano y de inicio de sesión, bibliotecas incluidas, y los archivos que se añadieron, se eliminaron o cambiaron de tamaño. `duo diff` hace lo mismo desde Terminal para dos copias cualesquiera de una app.

**Reabrir te avisa cuando el actualizador de una app no aplicó la actualización.** Si la app se cierra y la actualización nunca llega, su fila ahora lo dice y sigue ofreciendo Reabrir. Antes, el indicador se detenía sin decir nada.

**Cherry Studio vuelve a mostrar su versión más reciente.** Después de que Cherry Studio renombrara sus descargas para Mac, DuoUpdater tomaba una versión anterior por la más reciente: las copias recientes aparecían como actualizadas y a las más antiguas se les ofrecía esa compilación anterior.

**Las actualizaciones de la App Store ya no se atascan detrás de un asistente que no responde.** Cuando el asistente de DuoUpdater dejaba de responder, la actualización se quedaba en el 0 % y todas las actualizaciones de la App Store en cola esperaban hasta que salías de DuoUpdater.

**Actualizar todo ya no reabre las apps que has ignorado.** Con «Reabrir automáticamente las apps actualizadas» activado, el final de un lote podía cerrar y volver a abrir una app ignorada, o una cuya versión descargada habías omitido.

**Tinycast y SuperCmd ya son compatibles.** DuoUpdater te avisa cuando sale una nueva versión de Tinycast o de su beta, y ahora reconoce el SuperCmd original de código abierto además de SuperCmd 2. Las notas de la versión de Kimi Code también se muestran ahora.

**Las notas de la versión corresponden a la versión ofrecida.** La página de notas más reciente de VS Code aparecía vacía y, justo después de salir una versión nueva, el panel de notas podía mostrar las de la versión anterior.

**El Registro de versiones ya no añade la misma versión en cada arranque.** Apps como Claude, Raycast y Cline sumaban una entrada duplicada cada vez que se iniciaba DuoUpdater.

**La barra lateral del workbench se divide en las pestañas Apps, Brew y Reversión.** Haz clic en una pestaña o arrastra sobre ellas para cambiar; la búsqueda filtra las tres a la vez.

**Por dentro.** Reabrir y Revertir sobre la misma app ya no se pisan; un feed de actualizaciones ya no puede hacer que DuoUpdater borre archivos fuera de su carpeta de descargas; las comprobaciones en segundo plano ya no corren el riesgo de que macOS pida acceso a los datos de otras apps; un número muy grande en el filtro de Solicitudes ya no cierra la app; y la barra de menús respeta ahora una solicitud de administrador que rechazaste en `duo install`.

## 0.3.97

**Las actualizaciones de iStat Menus se detectan correctamente.** Cuando iStat Menus volvía a publicar una actualización, DuoUpdater podía seguir ofreciéndola después de instalarla, y volver a pulsar Actualizar terminaba en un error.

**Memoh Desktop ya es compatible.** DuoUpdater te avisa cuando sale una nueva versión y puede actualizarla con un clic.

**Actualizar todo ya no te pide reabrir una app de la App Store que ya se ha vuelto a abrir.** Cuando la App Store cierra una app y la vuelve a abrir con su nueva versión, su fila la muestra como actualizada al momento, en lugar de decir «Reabrir ahora» hasta que terminaba todo el lote.

## 0.3.96

**Una app que ya ha descargado su propia actualización ya no la descarga dos veces.** Algunas apps descargan una actualización en segundo plano y luego esperan a que las reinicies. Pulsa Actualizar en DuoUpdater y ahora instala la copia que ya está en tu disco: la actualización se completa en segundos y no hay que descargar nada. Antes, DuoUpdater volvía a descargar la misma versión.

**Cua Driver y Petex ya son compatibles.** DuoUpdater te avisa cuando cualquiera de las dos publica una nueva versión, y Cua Driver además se actualiza con un clic y muestra sus notas de la versión.

**La misma actualización ya no te avisa una y otra vez.** Cuando el servidor de un desarrollador alternaba entre dos versiones, cada comprobación parecía una actualización nueva y enviaba otra notificación.

**Un paquete que se acaba de instalar ya no ofrece volver a instalarse.** Su fila seguía diciendo que el paquete descargado se volvería a abrir.

**DuoUpdater ahora requiere macOS 15 Sequoia o posterior.** Un Mac que siga en macOS 14 conserva la versión que tiene y deja de recibir actualizaciones; todos los Mac con Apple silicon pueden actualizarse a un macOS compatible.

**Por dentro.** Las comprobaciones periódicas ya no consultan los enlaces de descarga por adelantado, lo que podía ocultar por un momento un botón Actualizar que funcionaba cuando el servidor de descarga de un desarrollador no respondía a tiempo.

## 0.3.95

**Aside ya es compatible.** DuoUpdater te avisa cuando sale una nueva versión del navegador Aside y muestra sus notas de la versión.

**Ya no se ofrecen actualizaciones que tu macOS no puede ejecutar, y la fila ahora explica por qué.** Cuando un desarrollador indica qué versiones de macOS admite una versión, DuoUpdater lo respeta: tras actualizar macOS, Little Snitch ya no ofrece una versión limitada a un sistema anterior al tuyo; Xcode ya no ofrece una versión que requiere un macOS más reciente que el tuyo; y un paquete de instalación cuya app requiere un macOS más reciente se rechaza, en lugar de instalar una app que no se abre. Las filas que antes mostraban un guion en blanco ahora dicen «Aún no para este macOS» o «Requiere un macOS más reciente», con los detalles a un clic.

**Consulta con qué SDK se compiló cada app.** Haz clic en la marca junto al nombre de una app y sus detalles ahora dicen, por ejemplo, «Compilada con el SDK de macOS 27.0.»: muy útil para saber qué apps ya se han recompilado para el macOS más reciente.

**Las apps de Homebrew que se publican en dos paquetes —uno para sistemas anteriores y otro para el más reciente— ahora se leen desde el correcto.** OnyX se divide así para macOS 27, y DuoUpdater solo miraba el paquete para sistemas anteriores: o no mostraba OnyX en absoluto, o lo daba por actualizado frente a una versión que Homebrew se niega a instalar en 27. Ahora DuoUpdater sigue el de los dos que tengas instalado.

**Las betas de TestFlight ya no pierden su actualización cuando se abre TestFlight.** Una beta con una nueva build esperando podía volver a «actualizada» y quedarse así hasta que abrías TestFlight otra vez.

**Las actualizaciones con un clic de Dropbox y ToDesk descargan el archivo correcto.** En Mac con Apple silicon, Dropbox descargaba la versión solo para Intel, que luego la comprobación de seguridad rechazaba; a ToDesk se le ofrecía la versión de acceso anticipado que solo reciben algunos usuarios, en lugar de la versión general.

**Reabrir completa la actualización de Spotify al instante.** Cuando Spotify ya había descargado su propia actualización, Reabrir se quedaba girando varios minutos antes de que la actualización se aplicara.

**Las versiones beta avanzan hacia sus versiones finales.** A una beta de Xcode se le ofrece su versión candidata en lugar de mostrarse como actualizada; las betas de CotEditor ven sus versiones candidatas; y a una beta de Carbon Copy Cloner cuyo ciclo de pruebas ha terminado se le ofrece la versión en la que se convirtió, en lugar de una comprobación fallida.

**Las notas de la versión coinciden con la versión que tienes.** Blender 5.2 mostraba las notas de 5.1, y Raycast 1.x las de 2.x. «Abrir página» de Gemini ahora abre la página actual de escritorio de Google en lugar de un error.

**Ajustes explica cada opción justo a su lado.** Las notas largas bajo secciones enteras se han sustituido por una línea breve bajo cada control, y los selectores describen solo la opción elegida.

**La app ahora escribe su nombre como DuoUpdater**, igual que el sitio web.

## 0.3.94

**Los paquetes de Homebrew de taps en los que no confías vuelven a aparecer.** Desde Homebrew 6, brew omite en silencio los paquetes de taps sin confianza al listar lo instalado, así que desaparecían de DuoUpdater sin explicación. Ahora aparecen como «Sin comprobar · tap sin confianza», con el comando `brew trust` listo para copiar, y en cuanto lo ejecutas (o una actualización) en Terminal, la ventana se pone al día al volver a ella.

**Las apps que necesitan contraseña de administrador para actualizarse ya no se actualizan dos veces.** Cuando una app como Tailscale ya había descargado su propia actualización y esperaba un reinicio, DuoUpdater no lo veía y seguía ofreciendo Actualizar, lo que podía chocar con el instalador de la propia app. Ahora la fila ofrece Reabrir, y Actualizar todo la deja en paz.

**La sección de Homebrew ahora puede actualizar el propio Homebrew.** Cuando sale una nueva versión de Homebrew, una fila en la parte superior ofrece ejecutar `brew update` por ti. Si has definido `HOMEBREW_NO_AUTO_UPDATE`, no aparece.

**Una actualización de Homebrew fallida ahora muestra el error real de brew.** Antes la fila mostraba el consejo que brew imprime después del error, o nada, así que un mensaje como «tus Command Line Tools están demasiado desactualizadas» nunca te llegaba. Además, actualizar varios paquetes a la vez ya no da por terminado el proceso antes de tiempo.

**El icono de la barra de menús cuenta más allá de 50.** Con más de 50 actualizaciones pendientes, antes se quedaba en 50.

**Notas de la versión: las de Claude se agrupan en New, Improved y Fixed, igual que en el propio Claude; las de Mac Mouse Fix se muestran como texto en lugar de una página incrustada; y la app oficial de Homebrew ya tiene notas.**

**`duo check` ya no dice «Everything is up to date.» cuando en realidad no pudo comprobar.** Ahora avisa cuando no pudo leer TestFlight o cuando se abandonó el análisis de apps.

## 0.3.93

**Las notas de versión ahora aparecen en tu idioma cuando una app las publica en varios.** Algunas apps publican sus notas traducidas junto a cada versión; DuoUpdater tomaba la traducción que la app listara primero o última, así que las notas de una app se leían en alemán para todo el mundo y las de otra cambiaban de idioma de una versión a la siguiente.

**Las apps que han añadido una versión para Mac ya no aparecen como «No es compatible con este Mac».** Una app de iPhone o iPad que ejecutas en Apple silicon quedaba marcada por error justo cuando su desarrollador publicaba una compilación nativa para Mac, es decir, el único cambio que hace la actualización más accesible, no menos.

**Una app de la App Store que además pruebas en beta ya no se confunde con una compilación de TestFlight.** Cuando un desarrollador promocionaba una beta sin cambios, ambas llevaban el mismo número de compilación y tu copia comprada quedaba en manos de TestFlight, de modo que la App Store nunca podía ofrecerle una actualización.

**Una actualización de la App Store que necesita un macOS más nuevo del que tienes ahora lo dice.** Antes, la fila se ofrecía a instalarla igualmente y la App Store la rechazaba en el último paso, sin nada en pantalla que explicara por qué.

**La ventana de «Solicitudes» ahora muestra hasta dónde llega realmente su registro y señala los periodos que no puede cubrir por completo.** Antes, elegir «Últimos 30 días» en un registro que solo llegaba a unas pocas horas atrás se veía exactamente igual que elegir «Últimas 24 horas», sin nada en pantalla que explicara por qué.

**Tú decides cuánto hace DuoUpdater con las betas de TestFlight, en Ajustes → General.** «Al actualizar» lee lo que TestFlight ya sabe y le pide una respuesta nueva cuando pulsas el botón para actualizar la lista; «Mantener al día» además deja que DuoUpdater pregunte por su cuenta, de modo que una beta de TestFlight instalada en segundo plano ya no se queda como un signo de interrogación hasta que actualices, y una compilación que te espera ya no pasa desapercibida detrás de un «actualizado»; «Desactivado» no lee nada y lo dice en esas filas en lugar de adivinar. Los Mac que ya tenían acceso total al disco empiezan en «Al actualizar», y el resto en «Desactivado».

**Abrir TestFlight tú mismo ya basta para que DuoUpdater se entere de lo que ha instalado.** Una beta que instalabas desde TestFlight se quedaba como un signo de interrogación hasta la siguiente actualización de la lista, y en macOS 27, donde el aviso «Listo para probar» de TestFlight ya no llega para las apps que ya tienes, eso podía ser cuestión de horas.

**Cline ya recibe actualizaciones, tanto en su versión estable como en la beta, y muestra sus notas de versión.** Hasta ahora se quedaba con un signo de interrogación en lugar de una versión: no publica ningún canal de actualizaciones de los que DuoUpdater sabe leer, y no existe un paquete de Homebrew para él. DuoUpdater ahora consulta la misma dirección que consulta el propio actualizador de Cline, así que la actualización que se te ofrece es la que Cline habría instalado por su cuenta, y la compilación beta se mantiene en la vía beta.

**Las notas de versión que agrupan los cambios bajo encabezados como «Añadido» y «Corregido» ahora conservan esos encabezados.** Antes, todos los grupos se fundían en una sola lista plana, así que no podías distinguir qué cambios eran novedades y cuáles corrección de errores.

**Mac Mouse Fix ahora ofrece sus versiones beta si has activado «Get Beta Versions» en sus propios ajustes generales.** Antes, DuoUpdater solo podía ver las versiones normales de Mac Mouse Fix, así que una compilación beta pasaba desapercibida hasta que salía la siguiente versión normal.

**Las apps cuyo número de compilación es un simple contador ya no ocultan sus propias versiones de mantenimiento.** En una app que informaba de una versión como 12.10 con la compilación 282987, una versión 12.10.1 se leía como «ya está actualizada».

**Una nueva compilación de una app que conserva el mismo nombre de versión se vuelve a anunciar.** Una vez anunciada una compilación, todas las posteriores con ese mismo nombre llegaban en silencio: la fila se encendía y el distintivo la contaba, pero nunca llegaba ningún aviso.

**«Actualizar todo» ahora solo cuenta las apps que realmente se actualizaron.** Una app que abre el Instalador de Apple para que termines tú se contaba como hecha mientras su ventana seguía abierta, así que «se han actualizado 2 apps» podía significar que aún no había cambiado nada.

**Una actualización que llegó a su destino pero dejó un resto detrás ahora se informa como instalada, y no como «concede Gestión de apps».** La nueva versión ya estaba en marcha mientras la fila te enviaba a Ajustes del Sistema.

**Detener «Actualizar todo» ahora detiene también la descarga en curso.** Antes, una transferencia de varios gigabytes seguía hasta el final, reintentándolo hasta cinco veces, y solo entonces se daba cuenta de que se había cancelado.

**Las notas de versión ya no se mezclan entre dos apps que comparten una misma página de cambios, y se mantienen al día tras una actualización en las apps cuyas notas viven en páginas por versión.** Antigravity y Antigravity IDE podían mostrar cada una las notas de la otra durante un cuarto de hora; Thunderbird, WeChat, Opera y algunas más seguían mostrando las notas de la versión anterior un rato después de actualizar.

**La búsqueda en la lista de apps ignora los acentos, como ya hacía la búsqueda de Ajustes.** Escribir «cafe» ahora encuentra «Café».

**La página de «Diagnóstico» muestra una línea de estado por cada canal de versiones.** Una regla de beta o de vista previa averiada quedaba oculta detrás de su hermana estable, que sí funcionaba.

**Una respuesta «prohibido» de GitHub ya no se informa como un límite de peticiones.** Un repositorio que pasó a ser privado o un token al que le falta un permiso te empujaban a añadir un token que no habría servido de nada.

**«Reabrir» ya no se ofrece en una app que se actualiza sola cuando la compilación en espera es más antigua que la que está en marcha.**

**Por dentro.** Las instalaciones, las copias de seguridad y las comprobaciones de paquetes ya no ocupan los hilos con los que funciona el resto de la app, así que el menú sigue respondiendo mientras una está en curso; el menú también se mantiene fluido mientras hay una descarga grande en marcha; el «Registro de versiones» cuenta todas las publicaciones que un proveedor lanza bajo un mismo nombre de versión; una copia de seguridad para revertir se rechaza en lugar de guardarse cuando le faltaría el propio ejecutable de la app; el primer arranque en un Mac recién estrenado ya no registra errores espurios de base de datos; `duo verify` y `duo reconcile` ahora informan de un historial de cambios cuyas entradas se han venido abajo y de una dirección de instalación que lleva días fallando; un comando `duo` atascado abandona su escaneo a los veinte segundos en vez de quedarse colgado.

## 0.3.92

**Algunas apps que se actualizan solas ya no parecen estar al día cuando hay una versión más nueva.** En las apps cuya información de actualización está detrás de un servidor de descargas que tarda en refrescarse, DuoUpdater podía seguir viendo una versión anterior durante días después de una publicación.

**Las notas de versión de Kimi ya aparecen en DuoUpdater.**

**Las actualizaciones de CodeEdit ya aparecen.** Una versión más nueva de CodeEdit dejaba su fila con un signo de interrogación en lugar de ofrecer la actualización.

**Por dentro.** La lista de Homebrew del menú se rellena más rápido, y los comandos `duo` arrancan más rápido.

## 0.3.91

**«Comprobar de nuevo» en una beta de TestFlight ya da la respuesta real.** Antes convertía la fila en un signo de interrogación hasta la siguiente actualización.

**Las betas de TestFlight conservan su respuesta mientras el botón para actualizar la lista consulta a TestFlight.** Antes, durante unos segundos, podían convertirse todas en signos de interrogación.

## 0.3.90

**super.engineering ya está cubierto: comprobación de actualizaciones, notas de versión e instalación con un clic.** Una nueva compilación nightly aparece en la lista con lo que cambió en ella, y «Actualizar» la instala por ti.

**Microsoft Edge Beta podía ofrecerte una compilación estable de Edge.** Durante un breve periodo en el que el feed beta de Microsoft estuvo vacío, la fila mostraba una versión estable, y actualizar la habría instalado encima de tu beta.

**Las betas de TestFlight ya muestran las actualizaciones que TestFlight tiene para ellas, incluidas las betas de apps de iPhone y iPad.** El botón para actualizar la lista consulta a TestFlight en segundo plano, una actualización ya no desaparece a los pocos minutos de encontrarla y el botón de TestFlight abre la página de esa beta.

**Cuando DuoUpdater no puede saber si una beta de TestFlight está al día, te lo dice.** La fila muestra un signo de interrogación en lugar de decir que está al día, por ejemplo cuando no has iniciado sesión en TestFlight o ya no estás probando esa beta.

**DuoUpdater ahora te explica el acceso total al disco, y sin él ya nada te molesta.** Sin él, DuoUpdater deja de provocar las advertencias de macOS sobre la lectura de datos de otras apps; si una beta de TestFlight o CotEditor lo necesita, te dice una sola vez por qué hace falta y dónde concederlo.

**«Reabrir» desaparece en cuanto una app actualizada se ha cerrado.** Una app que dejaba un proceso auxiliar en marcha seguía pidiendo que se la reabriera mucho después de que su actualización hubiera surtido efecto.

**Un aviso de privacidad de macOS sin contestar ya no deja atascada la comprobación de actualizaciones.** La comprobación sigue adelante sin el ajuste de esa app.

**Las notas de versión de Rockxy y Ollama vuelven a estar completas.** Las de Rockxy abarcan sus publicaciones recientes en lugar de solo la última, y la publicación más reciente de Ollama ya no queda fuera.

**`duo`, el acompañante opcional de línea de comandos, maneja mejor TestFlight.** `--refresh-testflight` funciona tanto si TestFlight está abierto como si no, sin adueñarse de tu pantalla, y `duo check` deja de decir que una beta está al día cuando TestFlight ya ha anunciado una compilación más nueva.

## 0.3.89

**Telegram Desktop vuelve a recibir comprobaciones de actualización.** Telegram cambió el nombre del archivo que publica y la fila ya no podía leer una versión en él, así que mostraba un fallo de comprobación en lugar de la actualización que esperaba detrás.

**Una app de iPhone o iPad instalada desde TestFlight se reconoce como tal.** DuoUpdater la tomaba por una compra de la App Store, así que la fila señalaba al gestor equivocado mientras se preguntaba a la tienda por una ficha que no existe: en cada comprobación, mientras la app siguiera instalada.

**Una beta de TestFlight se marca con el icono del propio TestFlight.** Las filas de las que se ocupa la App Store ya llevaban el icono de la tienda; las que atiende TestFlight escribían el nombre en su lugar, así que el mismo tipo de fila quedaba marcado de dos maneras distintas.

**La cabecera de la ventana Red se queda quieta al cambiar de pestaña.** Sus dos pestañas colocaban el titular a alturas ligeramente distintas, de modo que pasar de una a otra hacía que la ventana pareciera dar un salto.

## 0.3.88

**Desplazarse por toda la lista de apps vuelve a ser fluido.** Un desplazamiento rápido por la lista completa perdía fotogramas; ahora cada fila indica su altura sin tener que construirse primero.

**Las notas de versión de una app de la App Store vienen siempre de la App Store.** Cuando la consulta de la tienda para una app no encontraba nada o fallaba, la ventana podía recurrir a las notas de la otra vía de distribución de esa app —otra compilación, con sus propios números de versión— y describía así una publicación que tu copia nunca iba a recibir.

**A Windscribe en su canal Beta o Guinea Pig se le ofrecen las compilaciones de ese canal.** DuoUpdater lee el canal de actualización que elegiste en los ajustes del propio Windscribe, así que a una copia que sigue una línea de prelanzamiento ya no se le dice que está al día mientras hay compilaciones más nuevas en esa línea. La ventana también muestra las notas de esas compilaciones de prelanzamiento, que antes solo listaba para las estables.

**Windscribe ya recibe comprobaciones de actualización, con sus notas de versión.** Una copia que ejecuta una compilación antigua aparece con la versión a la que puede pasar y qué cambió en ella; antes, DuoUpdater no tenía forma de ver la versión de Windscribe. La actualización se sigue haciendo con el instalador del propio Windscribe, que configura partes que viven fuera de la app.

**Ya no se aplica una actualización a una app que desapareció mientras hacías clic.** Si la app se desinstala, se reemplaza o deja de poder leerse entre el clic y el inicio de la instalación, DuoUpdater se detiene y lo dice, en lugar de instalar igualmente sobre esa ubicación.

**`duo`, el acompañante opcional de línea de comandos, deja de dar por terminada una instalación por paquete antes de que lo esté.** Instalar una app que se distribuye como `.pkg` abre el instalador de macOS y te deja el resto a ti, pero el resumen la contaba como instalada: «1 installed» cuando todavía no se había reemplazado nada. Ahora se cuentan por separado. Su salida `--json` también etiqueta cada línea con lo que ocurrió con esa app, de modo que un script ya no tiene que leer la explicación en inglés para distinguir un fallo de un salto deliberado.

**Under the hood.** La recomprobación justo antes de instalar que protege una actualización de un clic protege ahora también a `duo install`; y las comprobaciones que una descarga debe superar antes de reemplazar una app están en un solo sitio para las dos vías que las usan.

## 0.3.87

**Pulsar «Actualizar» ya no se queda en nada cuando una fuente de actualizaciones se contradice.** Si la comprobación que se lanza al pulsar devuelve una versión más antigua que la que ofrecía la fila, DuoUpdater ahora lo indica y mantiene la actualización disponible. Antes daba la aplicación por actualizada y la quitaba de la lista, y la misma actualización reaparecía en la comprobación siguiente.

**Las actualizaciones de Fork vuelven a ofrecerse cuando Fork está en su canal Develop.** DuoUpdater leía al revés la preferencia de canal de Fork y seguía su feed Stable, que va bastante por detrás: una copia en Develop figuraba como actualizada mientras Fork ya ofrecía una versión más reciente.

**Mac Performance Monitor ya muestra sus notas de versión.** La aplicación las publica en su repositorio y no en el feed que leemos, así que la ventana no tenía nada que mostrar.

**CotEditor ya está cubierto, tanto en su línea de versiones finales como en la de betas.** La línea que sigue cada copia se deduce de la versión instalada y del propio ajuste de CotEditor «Update to prereleases when available», de modo que una copia beta recibe la siguiente beta en lugar de una versión final que la haría retroceder.

**Una aplicación instalada desde la App Store nunca recibe la oferta de descargarla de otro sitio.** Cuando la consulta a la tienda falla o vuelve vacía, la fila indica ahora que la tienda se encarga de ella, sin número de versión. Antes la comprobación podía recurrir a la otra vía de distribución de la aplicación —una compilación distinta con su propia numeración— y ofrecerse a instalarla encima de la copia de la tienda.

**A una aplicación nunca se le ofrece una actualización que la llevaría a una versión anterior.** Algunos feeds sitúan una versión estable por encima de una preliminar que en realidad va por delante, e instalarla habría hecho retroceder la aplicación.

**Un error largo en una fila ya no empuja hacia abajo el resto de la lista.** Se limita a dos líneas y el texto completo aparece al pasar el puntero.

## 0.3.86

**Se cubren cuatro apps más: WhatCable, Qoder IDE, Qoder y Yaak.** Cada una tiene comprobación de actualizaciones e instalación con un clic, y sus notas de versión se leen en la ventana como texto en vez de como una página incrustada.

**Las dos apps de Mac de Qoder ya se distinguen.** El IDE y la app de escritorio comparten nombre y página de descarga, pero salen en líneas de versión distintas, así que ahora cada una se sigue por su cuenta.

**Las betas de WhatCable y de Yaak se siguen en su propio canal.** Una copia con una beta no tenía ninguna fuente y se quedaba en «Failed»; ahora se le ofrece la siguiente beta, con notas de versión separadas de las de las versiones finales. En WhatCable eso incluye además la versión final en la que acaba convirtiéndose una beta: aceptarla pasa la copia al canal final.

## 0.3.85

**Comprobar tus apps de la App Store gasta una fracción de la red que gastaba.** Cada comprobación volvía a pedir la página de producto de cada app de la App Store; ahora las páginas se conservan una hora y se pregunta a la tienda por todas tus apps en unas pocas peticiones en vez de una por app. Con un intervalo de comprobación de cinco minutos eso supone alrededor de un tercio menos de tráfico en total; con el intervalo por omisión de seis horas las páginas siguen caducando entre comprobaciones, así que ahí el ahorro es menor.

**Volver a comprobar una sola app ya no vuelve a pedir todas las de la App Store.** Un solo «Check Again» descartaba todas las páginas de producto guardadas, de modo que la siguiente comprobación programada las pagaba todas; ahora solo actualiza la app por la que preguntaste.

**Comprobar apps que se distribuyen por GitHub cuesta una fracción de la red que costaba.** Cada comprobación volvía a descargar la descripción completa de cada versión aunque no se hubiera publicado nada; ahora se pregunta a GitHub si la versión ha cambiado desde la última vez y no se descarga nada si no. Una vez al día se relee cada versión entera, así que una versión retirada se nota en menos de un día.

**Las apps seguidas en un canal beta o nightly de GitHub piden ahora una versión en vez de una página de versiones.** La más reciente es la respuesta casi siempre, y la página completa solo se pide en las rondas en que no lo es.

**La comprobación de actualizaciones de Vorssaint ya no pasa por una redirección.** Su repositorio cambió de nombre, y seguir el nombre antiguo dejaba la petición en el límite anónimo de GitHub sin decirlo; ahora la comprobación va directa al nombre nuevo.

**Por dentro.** El artefacto de la versión se compila, se firma y se notariza en un Mac alojado por GitHub, con una procedencia de compilación que cualquiera puede verificar, y el registro de peticiones distingue una respuesta guardada de una que salió a la red.

## 0.3.84
**Los registros de peticiones que exportas ya no llevan tu nombre de cuenta.** Cada fila de una app instalada en tu carpeta personal escribía la ruta completa; ahora muestra `~`, sea cual sea la forma en que extraigas el registro.

**La pestaña «Requests» ahora dice qué incluye y qué no.** Registra las peticiones que hace el propio DuoUpdater. Una página de notas de versión carga sus propias imágenes y tipografías, y las actualizaciones de la App Store y de Homebrew las realizan herramientas aparte: nada de eso aparece ahí, y ahora la ventana lo dice en vez de dejar que lo supongas.

**«Copy URL» ahora escapa la dirección que te da.** Las rutas con un espacio —las descargas de Firefox, Thunderbird y Bartender, entre otras— se copiaban tal cual: un navegador lo corrige, la línea de comandos no.

**La fila beta de CapCut ya no informa de una comprobación fallida.** Entre una beta y la siguiente —cuando una pasa a versión final y la próxima aún no ha abierto— su fabricante no publica nada en ese canal. Eso aparecía como una fila roja y un «Retry» que no podía funcionar. Ahora la fila simplemente no tiene respuesta de esa fuente hasta que aparece la siguiente beta.

**Audacity ahora muestra la marca que dice con qué está hecha.** Arranca mediante un pequeño lanzador que cede el paso al programa real que tiene al lado, y la marca se leía del lanzador, que no enlaza nada.

**Las notas de versión de la App Store ahora llegan en tu idioma.** Siempre se obtenían en el idioma predeterminado de la tienda, así que un Mac configurado en chino o japonés las seguía leyendo en inglés.

**Las actualizaciones del propio DuoUpdater ahora aparecen a su nombre en la ventana «Network».** Su comprobación de versión, sus notas de versión y su descarga figuraban con la columna de app vacía.

**Por dentro.** Una credencial incluida en la ruta de una dirección web se elimina ahora antes de registrar la petición, igual que ya ocurría con las de la cadena de consulta.

## 0.3.83

**La ventana «Download Traffic» ahora se llama «Network» y tiene una segunda pestaña.** «Downloads» es el registro que ya tenía: lo que costó cada actualización como archivo. «Requests» es nuevo: cada petición que DuoUpdater hace por usted, para qué era, a qué app pertenecía y lo que costó, con un campo de filtro para preguntarle cosas al registro en lugar de recorrerlo. Las cifras de arriba responden a lo que tenga filtrado, no al total histórico.

**Comprobar si Spotify tiene actualizaciones casi no usa red.** Spotify no publica ningún archivo de versión, así que la comprobación lee la versión de un instalador reducido de dos megabytes, y se lo descargaba entero cada vez, a todas horas. Ahora pregunta primero si ese archivo ha cambiado y se salta la descarga cuando no.

**PDF Expert ya encuentra sus actualizaciones y muestra qué ha cambiado.** Leía una lista de versiones que su fabricante dejó de ampliar en 2022, así que se declaraba actualizado tuvieras la versión que tuvieras. Ahora sigue la lista que usa el propio actualizador de la aplicación y ahora muestra también las notas de versiones anteriores, no solo de la última.

**Las versiones preliminares de UTM ahora reciben sus propias actualizaciones, se instalan con un clic y muestran las notas correspondientes.** Antes una copia preliminar se comparaba con el canal final y se le decía, sin avisar, que estaba al día; ahora sigue su propia línea y vuelve al canal final en cuanto recibe la versión final de esa línea.

**Por dentro.** Las peticiones registradas pasaron al mismo almacén que el registro de descargas, así que las dos cuentas de una misma descarga ya no pueden separarse. Su registro actual se conserva intacto.

## 0.3.82

**Quince aplicaciones más están vigiladas, y todas menos una se instalan con un solo clic.** AgentsView, AnythingLLM, Chatbox, ChatGPT Classic, DSH Desktop, FluidVoice, GitHub Copilot, Kun, Meetily, Microsoft 365 Copilot, OpenLogi, OpenSuperWhisper, Paseo, T3 Code —en sus dos canales, alpha y nightly— y Vorssaint. La excepción es ChatGPT Classic: lo comprobamos por usted, pero trae un instalador que actualiza la app por su cuenta, así que esa actualización sigue estando en sus manos.

**Ocho aplicaciones muestran ahora sus notas de versión dentro de DuoUpdater en lugar de enviarle a una página web.** Xcode, Antigravity, Antigravity IDE, AnyDesk, AnythingLLM, Chatbox, Headlamp y Helium. En tres de ellas no había adónde enviarle: la página de AnyDesk responde con una comprobación antibots, quienes hacen Helium no publican ninguna página de notas, y Antigravity IDE no tenía enlace alguno.

**Las betas de Xcode dicen qué cambió en cada beta.** Antes la fila ofrecía un número de compilación y un enlace; ahora enumera las notas de Apple para la beta que tiene instalada y para todas las betas anteriores de esa misma versión.

## 0.3.81

**Word, Excel, PowerPoint, Outlook y OneNote ya se dan cuenta de que su actualización se instaló.** Estas cinco seguían ofreciendo reabrir un instalador que ya habías terminado y nunca llegaban a ofrecer el reinicio: esperar o volver a comprobar no lo resolvía.

**Una fila que espera reiniciarse vuelve a explicarse, en ambas ventanas.** Cuando una app iba por delante de lo que publica su proveedor y además esperaba un reinicio, la línea sobre el botón describía algo totalmente distinto; en las filas que esperaban el reinicio de «Actualizar todo», la ventana y el menú también se contradecían.

**Las etiquetas de estado ya no desplazan el nombre de la app en ruso.** Además, algunas etiquetas tomaban prestada la redacción de textos sin relación en todos los idiomas traducidos.

**Las notas de la versión ya aparecen para las apps cuyo proveedor fecha una publicación sin indicar la hora.** Antes esas publicaciones no dejaban rastro en ninguna parte.

**Una página de notas que nos negamos a abrir ahora dice por qué.** Antes se quedaba en blanco, lo que parecía exactamente una app que no publica notas.

**Las notas de la versión Nightly de WeChat DevTools ya no están vacías.**

**Por dentro.** El manejo de versiones y de fechas de publicación se unificó, de modo que un número de compilación nunca se lee como versión comercial y la cronología de publicaciones ya no inventa una hora que el proveedor nunca dio.

## 0.3.80

**Las comprobaciones fallidas ya se ven en la ventana.** La ventana no dibujaba nada para una fila cuya comprobación había fallado —ni para las que habías ignorado, aquellas cuya versión habías omitido, ni las que gestionan la App Store, Toolbox o TestFlight—, y eso se veía exactamente igual que «al día». Ahora las dos ventanas dicen lo mismo sobre la misma aplicación, y el botón para reintentar está en ambas.

**«Check Again» consulta, en cualquier fila, solo esa aplicación.** De paso vuelve a leer qué aplicaciones están abiertas: es la forma más rápida de corregir un punto verde que parece equivocado.

**Omitir una versión e ignorar una aplicación ahora se deshacen desde el menú contextual de la ventana.** Ambas filas pedían hacer clic derecho para deshacerlo, en una ventana cuyo menú no ofrecía nada de eso.

**La comprobación en segundo plano ya no te quita las notas de versión que estás leyendo.** La comprobación cada hora descartaba todas las notas ya cargadas, así que un panel abierto volvía al indicador de carga. Ahora solo vuelve a empezar si tú pides actualizar.

**Las descargas interrumpidas se comprueban antes de darlas por completas.** Se daba por buena tanto la respuesta de un servidor que reenviaba el archivo entero como la de uno que se cortaba antes de tiempo, y el problema aparecía un paso después, como una instalación desde un archivo dañado. Las descargas tras ciertos proxies, que fallaban de forma permanente, ahora funcionan.

**Actualizar una aplicación ya no vuelve a leer todas las aplicaciones del disco.** Cada clic hacía dos recorridos completos de todas tus aplicaciones solo para mirar la que habías señalado.

**Las notas de versión de Chrome ya no pueden quedarse bloqueadas.** Un rediseño corriente del blog de Google bastaba para detenerlas varios minutos; ahora cargan enseguida, sea cual sea el aspecto de la página.

**Un instalador ya descargado no se descarta para volver a bajarlo.** Cuando un proveedor escribía la misma versión de dos maneras (`v1.2.3` y `1.2.3`), el paquete en espera no se reconocía, y «Reiniciar» podía quedarse esperando un reemplazo que ya había ocurrido.

**Una instalación con permisos de administrador que falla ya no se confunde con una cancelación tuya.** No se mostraba ningún error, y esa aplicación dejaba de ofrecer en silencio la actualización con un clic hasta que volvías a pedir permisos de administrador desde el menú de su fila.

**El punto verde de «en ejecución» ya detecta todas las aplicaciones.** macOS no anuncia en absoluto la apertura o el cierre de algunas, y su punto se quedaba equivocado hasta que algo ajeno lo refrescaba.

**«Actualizar todo» ya no aparece y desaparece durante una actualización**, y una aplicación que actualices a mitad de la comprobación no vuelve a ofrecer la actualización que ya instaló.

**Si la comprobación falla justo al pulsar Actualizar, se te dice**, en lugar de archivarlo como «nada que hacer».

**Por dentro.** Las fechas de publicación escritas en formatos poco habituales se leen correctamente, la comprobación de direcciones de las páginas de notas de versión cubre todas las escrituras equivalentes, y el registro rutinario ya no toca el disco cada vez que se abre o se cierra cualquier aplicación en tu Mac.

## 0.3.79

**La marca de Docker ahora describe la interfaz de Docker y no su servicio en segundo plano.** La fila decía «nativa»; pero Docker Desktop es una app de Electron. Esa marca se lee del paquete de la app, y el paquete de Docker es una envoltura: el programa que nombra es un servicio en segundo plano escrito en Go, no lleva ningún framework propio, y la app que dibuja realmente las ventanas está un nivel más adentro. Todo se leía correctamente — solo que del archivo equivocado. DuoUpdater mira ahora dentro de la app anidada, pero solo cuando la exterior no aporta nada por sí misma y contiene exactamente una app de ese tipo que demuestre con qué está construida; así, un proceso auxiliar distribuido junto a una interfaz real sigue sin poder prestarle su identidad a su anfitrión. Docker se lee como Electron 42.5.0 y, de las ciento cuarenta y seis apps de la lista en la máquina donde se escribió esto, es la única fila que cambia.

**Las notas de versión de CleanShot X vuelven a leerse — incluidas las de la 5.0.** CleanShot publicó su mayor actualización en años y de paso reconstruyó su página de novedades: la fecha pasó por encima del número de versión, aparecieron dos capas nuevas a su alrededor, y una versión de funciones mete ahora una introducción y dos enlaces de vídeo entre la versión y su lista de cambios. La regla de lectura que usaba DuoUpdater dejó de coincidir con nada de eso. Lo que lo hacía peor que un panel vacío es que no parecía vacío: las notas ya guardadas de la versión anterior seguían en pantalla bajo el título de la nueva — el panel decía «5.0» sobre los cambios de la 4.8.10, y en ningún sitio se advertía.

**Las notas guardadas antes de que se publicara una versión ahora se releen en lugar de creerse para siempre.** Esta es la otra mitad de la misma historia. DuoUpdater supo que la 5.0 existía seis minutos antes de que CleanShot publicara su contenido, guardó la página tal como estaba y la archivó bajo 5.0 — y desde entonces cada comprobación encontraba algo ya guardado y no volvía a mirar. Las notas guardadas se confirman ahora con el proveedor una vez por sesión antes de darlas por definitivas, de modo que una versión cuyas notas llegan tarde se completa sola en la siguiente visita en vez de quedarse equivocada.

**Lo que abras desde la barra de menús ahora se abre al primer clic.** Elegir «Novedades» en una fila — o los Ajustes, o el registro de versiones — no hacía absolutamente nada la primera vez, y funcionaba a partir del segundo clic. Volver a abrir el menú convertía cada intento en «el primero» otra vez, así que para quien abre el menú, hace un clic y espera una ventana, nunca funcionó. El primer clic dentro del menú se gastaba en traer DuoUpdater al frente en lugar de hacer aquello a lo que apuntaba. La ventana que se abre también se mantiene delante ahora: se la traía al frente y se la empujaba hacia atrás en el mismo instante, que es la otra manera en que esto parecía un clic sin efecto.

## 0.3.78

**Una app que deja su propio nombre en blanco ahora recibe uno de todos modos.** Eudic (欧路词典) aparecía en la lista con un icono, una versión y nada en absoluto donde va el nombre. Su paquete sí declara un nombre visible — y lo deja vacío, porque los nombres reales están en las traducciones de la app — y DuoUpdater tomaba esa respuesta vacía por la respuesta en lugar de hacer la siguiente pregunta. Ahora recurre al otro nombre de la app, y después al nombre del propio archivo, de modo que ninguna fila se queda sin nombre. Aquí había una app afectada de ciento cincuenta; lo importante es que la información ya estaba ahí y se estaba omitiendo.

**El reinicio ahora te dice cuándo la app se negó a salir, en vez de parecer un clic que no hizo nada.** Si una app tiene una ventana esperándote — un aviso para guardar, una hoja de inicio de sesión, algún diálogo —, macOS no la dejará salir, y desde este lado no hay nada que hacer: es la ventana de la app. DuoUpdater antes daba vueltas treinta segundos y luego devolvía el mismo botón sin explicación alguna, lo cual se lee exactamente como un botón roto, así que la gente lo vuelve a pulsar. La fila ahora dice qué ha pasado y te remite a la app para que te ocupes de esa ventana. No se ha cambiado nada y la nueva versión ya está instalada, así que realmente solo falta el reinicio — y si simplemente cierras la app tú en los próximos diez minutos, DuoUpdater se da cuenta y la vuelve a abrir en la versión nueva sin que pulses nada.

**Las notas de versión de 欧路词典 vuelven a ser de una versión, y no de dieciséis años de ellas.** La app publica todo su historial — cada versión hasta la 2.5.0 — dentro de las notas de la versión que sea la más reciente, de modo que el panel de detalles lo mostraba todo bajo el título «26.9.0» y había que pasar una década desplazándose para encontrar lo que acababa de cambiar. Ahora cada versión tiene su propia entrada en la lista, como la de cualquier otra app.

**La marca que dice con qué está hecha una app ahora exige una prueba para Tauri, no un parecido.** Tauri no deja nada que encontrar en un paquete — ni framework ni carpeta propia —, así que esa marca en concreto se deducía de cómo estaba empaquetada la app, más el hecho de que enlaza la vista web de Apple. Longbridge encaja con todo eso y no es Tauri: dibuja sus propias ventanas con el mismo renderizador que Zed, e integra una vista web solo para un rincón de su interfaz. DuoUpdater ahora lee la huella propia de Tauri en el binario antes de afirmarlo, de manera que una app se llama Tauri cuando lo es — y Longbridge se lee como lo que es: una app nativa de Mac.

**CapCut ya no se pone en rojo porque los servidores de ByteDance tuvieran medio segundo malo.** El punto de acceso al que DuoUpdater le pide la versión de CapCut responde con un código de éxito y luego, aproximadamente una de cada cincuenta veces, con un objeto de error en lugar de la respuesta: un tiempo de espera agotado dentro de la propia infraestructura de ByteDance, unos 390 bytes donde se esperaban 436 kilobytes. Desde este lado no había forma de distinguir eso de que CapCut hubiera cambiado la forma de su respuesta, así que la fila decía que la comprobación había fallado, lo cual se lee como «esto está roto y alguien tiene que arreglarlo» para algo que se arregla solo al siguiente intento. Esa forma concreta ahora se reconoce por lo que es: la petición se reintenta de inmediato, y solo se informa como un problema real si persiste durante cinco días.

## 0.3.77

**Cada app de la lista dice ahora con qué está hecha.** La fila de una app de la App Store siempre ha llevado el distintivo de la tienda, y todas las demás filas se veían iguales: una app con Sparkle, una app de Electron y una nativa eran indistinguibles. Ahora cada nombre lleva la marca de la propia tecnología —haz clic para ver su nombre y una frase, o pasa el cursor para el tooltip: Electron, Tauri, Flutter, Qt, Java, Chromium, Mac Catalyst, una app de iPhone sobre Apple silicon o una app nativa de Mac— junto con la versión del entorno cuando puede leerse como un hecho (Electron 42.4.1, Qt 6.2, el Chromium que la app incrusta, el Tauri con el que se construyó). Todo se lee del propio paquete —el framework que el empaquetador tuvo que incluir, el entorno que necesita su lanzador, las bibliotecas que enlaza el binario—, así que es un hecho sobre lo que está instalado y no una suposición a partir del nombre. Cuando un nombre largo no deja sitio, el símbolo se aparta en lugar de empujar el nombre a una segunda línea: la fila es del nombre. Todo esto se desactiva en Ajustes → General.

**LibreOffice ya no anuncia una vuelta atrás a la versión que ya tienes.** Su índice de descargas publica versiones de tres partes (`26.8.0`) mientras que la copia instalada informa de cuatro (`26.8.0.3`), y rellenar con un cero la parte que falta hacía que la copia instalada pareciera más nueva: la fila mostraba una nota discreta de "el proveedor va por detrás de ti" sobre una app que estaba exactamente al día. Una fuente que publica menos partes de las que informa la app se interpreta ahora como una descripción de la misma versión, no de una anterior; una vuelta atrás real se sigue anunciando.

**Un ajuste que ha traído una actualización ahora se señala a sí mismo una vez.** Una preferencia nueva en mitad de la ventana de Ajustes es una preferencia que nadie encuentra. Tras la actualización que la añadió, el engranaje de la barra de menús lleva un punto azul, la página donde vive lleva otro en la barra lateral, y el propio control lleva el suyo hasta que lo has mirado. Solo para quien de verdad actualizó hasta ella: una instalación nueva no recibe puntos sobre funciones que para ella son simplemente parte de la app.

## 0.3.76

**Las apps de Electron añadidas en la versión anterior ya se pueden actualizar de verdad con un clic.** 0.3.75 enseñó a DuoUpdater a leer el archivo que esas apps llevan dentro de sí, y lo leía: calculaba la versión nueva, la descarga correcta para tu Mac y la suma de verificación con la que comprobarla — y luego no tenía adónde enviar nada de eso. El botón de instalar no aparecía nunca, y `duo install` explicaba el rechazo con un motivo que no era el real. En esta versión la ruta de instalación queda conectada. En la práctica puede que no notes ninguna diferencia: esta lectura va detrás de todas las reglas escritas a mano, así que solo habla por una app que nada más cubra — y hoy, en la máquina donde se compiló esto, no hay ninguna. Importa para la app que instales mañana y para la que nadie haya escrito una regla.

**Una descarga que te sacaría de una compilación nativa ahora se rechaza.** Apple Silicon todavía puede ejecutar apps de Intel mediante traducción, lo que significa que una descarga solo para Intel superaba la comprobación de «¿esto funciona en tu Mac?» y se instalaba sin problemas — dejándote con una copia traducida de una app que venía ejecutándose de forma nativa, en silencio, y repitiendo lo mismo en cada actualización futura. Ahora toda instalación en el sitio compara lo que tienes con lo que llegó y rechaza ese cambio. En sentido contrario, o de una compilación universal a una de Apple Silicon, es lo normal y se sigue permitiendo.

**Cuando no puede demostrar de qué arquitectura es una descarga, ahora declina en vez de adivinar.** Algunos proveedores publican una compilación para Apple Silicon junto a la predeterminada, y la única forma de saber que la predeterminada es la de Intel es advertir que existe la otra. Si esa segunda comprobación no vuelve limpia — el servidor del proveedor la rechaza, se corta la conexión, o ambas discrepan sobre qué versión son — DuoUpdater ya no trata ese silencio como una respuesta. Te dice la versión y no ofrece instalación, que es el resultado honesto.

**Una regla rota ya no puede desaparecer de Diagnóstico.** En apps cubiertas a la vez por una regla escrita a mano y por la nueva lectura — que son la mayoría, deliberadamente — un fallo de la regla quedaba anulado porque la lectura acertaba justo después, así que una app cuya regla se había roto de verdad seguía leyéndose como sana. Ahora se registran por separado. La nueva lectura además informa por primera vez de sus propios fallos: en la máquina donde se compiló esto, tres apps apuntaban a direcciones que llevan tiempo devolviendo «no encontrado», y nada lo había dicho en voz alta hasta ahora.

**Las filas que ven una actualización pero no pueden instalarla ahora ofrecen lo mismo en los dos sitios.** La barra de menús mostraba un botón que decía «Abrir» y abría el Finder, y la ventana no mostraba nada para esa misma fila.

## 0.3.75

**Las aplicaciones creadas con Electron ahora se reconocen sin que nadie tenga que anotarlas antes.** Muchísimas aplicaciones de Mac llevan dentro un pequeño archivo que indica dónde están sus actualizaciones. Hasta ahora DuoUpdater solo conocía aquellas para las que alguien había escrito una regla a mano: todas las demás aparecían en tu lista sin número de versión y sin forma alguna de avisarte de que había salido una nueva compilación. Ahora lee ese archivo directamente, igual que siempre ha leído el de Sparkle, de modo que una aplicación así queda cubierta el día que la instalas y no el día que alguien encuentra un rato.

**Las aplicaciones que ya tenían una regla escrita a mano no cambian.** El nuevo lector se sitúa detrás de ellas, así que solo puede rellenar un hueco; nunca sustituir algo que ya funcionaba.

**Dos detalles deciden si la descarga que ofrece es la correcta, y ambos se resolvieron comprobando aplicaciones reales en lugar de darlos por supuestos.** Algunos fabricantes marcan una compilación Intel como su descarga «principal» aunque publiquen otra para Apple Silicon junto a ella; otros dan a la compilación de Apple Silicon un nombre de archivo idéntico en apariencia al de Intel, de modo que el nombre no delata nada. DuoUpdater elige según la arquitectura y, cuando no puede asegurar que una descarga vaya a funcionar en tu Mac, te dice la versión y no ofrece la instalación, en lugar de entregarte algo que se instala sin problemas y luego no abre.

## 0.3.74

**Si usas la versión beta, la candidata a publicación o una compilación nightly de alguna aplicación, DuoUpdater llevaba tiempo vigilando la rama equivocada.** Determina en qué rama estás encontrando tu compilación en la propia lista de versiones del proveedor, pero una preversión suele conservar el mismo número de versión pública que la estable de la que procede, que es justo lo normal en una preversión. Así que la coincidencia caía en la entrada estable. El fallo era silencioso: en pantalla no aparecía nada raro, sencillamente dejabas de enterarte de la siguiente compilación de tu propia rama, y las notas de la versión que se te mostraban pertenecían a la línea estable. Se descubrió instalando las preversiones reales de Supacode y TypeWhisper y observando qué ocurría; ambas siguen ahora la rama en la que realmente están.

**La beta de CapCut mostraba una versión que no tenías.** La fila decía «9.3.4545 → 9.4.0-beta6» mientras que el propio CapCut, el Finder y cualquier otra herramienta de actualización llamaban a tu copia 9.4.0-beta5. Algunas aplicaciones guardan su versión real en un campo distinto al que usa la mayoría, y DuoUpdater leía en tu lado de la flecha el que parecía más limpio y en el lado del proveedor el verdadero. La actualización que ofrecía siempre era la correcta: lo único equivocado era la etiqueta. Ahora ambas mitades de la fila salen del mismo sitio, tanto en CapCut como en las otras siete aplicaciones construidas así.

**MacWhisper, GitHub Copilot for Xcode, TypeWhisper y OpenUsage ya muestran sus notas de versión.** Las cuatro tenían el panel de notas vacío: sus fuentes de actualización no incluyen nota alguna, algo que no se advirtió hasta contrastar cada una con lo que el proveedor publica de verdad. DuoUpdater lee ahora la propia página de notas de MacWhisper, el archivo de cambios de Copilot y el sitio de cambios de TypeWhisper, y apunta OpenUsage a su lista de versiones.

**Helium se actualiza ahora a través de su propio servicio, lo que trae su canal beta y descargas mucho más pequeñas.** Hasta ahora se seguía mediante la lista pública de versiones, donde solo aparecen las estables, así que quien usaba la beta de Helium recibía la estable. Su servicio también publica parches, de modo que una actualización corriente ocupa unos 40 MB en lugar de volver a descargar 124 MB. Comprobado con una compilación estable y una beta, y la descarga se verifica con la clave de firma que hay dentro de tu copia instalada antes de sustituir nada.

## 0.3.73

**Las versiones beta, developer y nightly de Firefox y Thunderbird ya se siguen bien: hasta hoy, ninguna de esas cinco vías de publicación había informado jamás de una sola actualización.** Se leían del archivo público de versiones de Mozilla, que solo publica la versión que se te muestra, y al instalar una beta se le quita el «b5»: una beta de Firefox se llama 155.0 durante todo el ciclo, así que la única pregunta que se hacía era «¿155.0b5 es más nueva que 155.0?», y la respuesta es no. Nightly era peor: Mozilla publica una cada día y todas se llaman 157.0a1, de modo que un ciclo de cuatro semanas no producía absolutamente nada. Ahora DuoUpdater pregunta al propio servicio de actualización de Mozilla, la misma dirección que usa el actualizador integrado de Firefox y que la aplicación lleva escrita dentro, y compara el identificador de compilación que ambos lados llevan. Comprobado antes de publicarlo contra las descargas reales de las cinco vías: el identificador que anuncia ese servicio es idéntico byte a byte al que hay dentro de tu copia; una beta con una compilación de retraso ya muestra su actualización, y una nightly construida más temprano ese mismo día también. Las versiones estable y ESR nunca se vieron afectadas y no se han tocado. Un límite que conviene decir con claridad: ese servicio no publica fecha de publicación, así que para estas cinco vías el registro de versiones sigue anotando cuándo vio DuoUpdater una compilación por primera vez, y no cuándo la publicó Mozilla.

## 0.3.72

**Wispr Flow, AionUi y Devin ahora se actualizan con un clic, en lugar de limitarse a avisar de que existe una versión nueva.** Los tres ya veían sus actualizaciones; ninguno podía aplicar una, con el motivo declarado de que el proveedor publica compilaciones separadas para Intel y Apple Silicon y DuoUpdater no tenía forma de elegir. Medido en lugar de supuesto, ese motivo no se sostenía: los puntos de acceso de los que se leen estos tres ya son los de Apple Silicon, y DuoUpdater solo funciona en Apple Silicon: nunca hubo elección que hacer. Cada descarga se obtuvo y se comprobó antes de conectarla: la aplicación correcta dentro, firmada por el mismo desarrollador que tu copia, notarizada por Apple, y la de AionUi contrastada además con la suma de verificación que publica su propio manifiesto. Después cada una se instaló de verdad sobre una copia más antigua y volvió en la versión nueva.

**Grok Bot ya se sigue: versiones nuevas y actualizaciones con un clic.** La app de escritorio de xAI la compila y la firma Anysphere, la empresa detrás de Cursor, y se actualiza a través del propio servicio de publicación de Cursor. Por eso ninguna de las vías habituales respondía por ella: sin feed de Sparkle, sin ficha en la App Store, sin repositorio público de versiones, y con un cask de Homebrew que devuelve la actualización a la propia app. DuoUpdater lee en su lugar el endpoint de versión del proveedor. Había otros dos endpoints y ambos se descartaron por motivos concretos: el que hay detrás del botón de descarga de x.ai no publica número de versión alguno, y el que usa el actualizador de la propia app responde con un cuerpo vacío cuando ya estás al día, un silencio que sería indistinguible de un endpoint roto. La descarga se comprobó antes de conectarla: la imagen de disco lleva la app correcta, firmada por el mismo desarrollador que tu copia y notarizada por Apple. Hay algo que deliberadamente no ofrece: las notas de la versión. xAI no publica ninguna para esta app, y el único changelog que sí publica pertenece a otro producto.

**Comet y Msty Studio también se actualizan con un clic, y una nueva comprobación vigila las aplicaciones que podrían hacerlo y no lo hacen.** Eran las dos últimas del grupo que veían sus actualizaciones sin poder aplicarlas, y ninguna necesitó nada nuevo: solo mirar con más atención lo que el proveedor envía en realidad. El enlace de descarga de Comet está firmado y caduca en una hora, así que el botón de actualizar apunta a la propia pasarela de Perplexity y el enlace se genera en el momento en que haces clic, no horas antes durante la comprobación. Msty publica cuatro descargas en un mismo archivo, con la versión Intel en primer lugar, y la huella usada para verificar la descarga se tomaba precisamente de esa primera entrada; ahora está ligada a la versión Apple Silicon que de verdad se obtiene, lo que además hace que una versión publicada entre la comprobación y el clic se detecte casi siempre en vez de instalarse en silencio. Ambas se descargaron y pasaron por las barreras de instalación reales antes de publicarse. La lección de fondo no tiene que ver con ninguna de las dos: nada en DuoUpdater podía advertir que una aplicación seguía en modo solo detección por un motivo que había dejado de ser cierto. El barrido nocturno de recetas ahora lo dice cuando una aplicación que solo se observa ya nos está entregando un instalador.

**QQ音乐 ahora está bajo seguimiento: nuevas versiones, actualizaciones con un clic y sus notas de versión en la ventana.** Ninguna de las rutas habituales respondía por ella. No publica ningún feed de Sparkle ni lleva el framework de Sparkle en absoluto; su cask de Homebrew le devuelve la actualización a la propia app; y el endpoint de actualización que nombra su propio binario responde con 200 y un cuerpo vacío a todo lo que se le puede preguntar — un silencio indistinguible de un endpoint roto, así que se dejó de lado. Lo que DuoUpdater lee en su lugar es el archivo de datos desde el que se construye la propia página de descarga del proveedor: esa página se envía como una carcasa vacía y se rellena a partir de ese archivo, que es también el único lugar donde existen las notas de versión — no hay blog, no hay appcast y no hay página por versión. Así que las notas se leen directamente de ahí y se renderizan en la propia ventana de DuoUpdater, y la actualización instala la imagen de disco notarizada nombrada en esa misma respuesta. Una trampa que merece la pena registrar: ese archivo todavía lleva un segundo registro para Mac, de hace seis años, junto al actual, así que ambas reglas se basan en el nombre de archivo versionado de la descarga para Mac y no en la palabra «Mac». Y un límite que merece la pena destacar claramente: el archivo publica la versión que se te muestra y nunca el número de build que hay debajo, así que un nuevo corte de una versión que mantiene su nombre es invisible aquí. No puede inventar una actualización que no existe; simplemente no puede ver ese tipo.

**TimeMachineEditor ahora está bajo seguimiento: nuevas versiones y actualizaciones con un clic.** Ninguna de las rutas habituales respondía por ella: sin feed de Sparkle (la app no lleva ni una dirección de feed ni el framework que la usaría), sin ficha en la App Store, sin repositorio público de versiones, y con un cask de Homebrew que le devuelve la actualización a la propia app. Lo que sí tiene es un pequeño sitio del proveedor cuyo único enlace de descarga declara la versión en su propio texto — la misma página, leída de la misma manera, en la que se apoya el propio chequeo de versión de Homebrew, así que esta es la superficie que el proveedor pretende y no una suposición. La actualización se instala como el propio paquete instalador del proveedor en lugar de como un simple intercambio de app, y eso es deliberado: la descarga también coloca un programador en segundo plano, una herramienta de línea de comandos y un launch daemon fuera de la propia app, así que reemplazar solo la app dejaría una copia nueva junto a un programador obsoleto sin nada que note el desajuste.

**Little Snitch ahora se rastrea, tanto en sus versiones estables como en sus nightly.** Object Development publica un archivo de versión al que recurre su propio actualizador — el mismo que lee Homebrew — y DuoUpdater lo lee directamente, porque Little Snitch no publica feed de Sparkle y su cask le devuelve la actualización a la propia app. Las dos versiones comparten una única identidad, lo que normalmente las haría imposibles de distinguir; esta se delata en el propio string de versión, donde un build nightly escribe la palabra completa («6.5 nightly (7301)») mientras el build estable se lee como un simple «6.4.1». Merece la pena decir lo que esto deliberadamente no hace: no instalará la actualización por ti. Little Snitch ejecuta una extensión del sistema y un servicio en segundo plano con privilegios junto a la app, y no se ha verificado en una máquina real si intercambiar solo la app deja eso intacto — así que DuoUpdater te dice que hay una versión nueva y te envía a la propia descarga del proveedor, en lugar de arriesgarse con un filtro de red.

**Carbon Copy Cloner ahora se rastrea, y no intentará moverte entre versiones mayores.** Bombich mantiene tres generaciones vivas a la vez — CCC 5, 6 y 7 — todas ellas reportando la misma identidad al sistema, lo que convierte «¿hay algo más nuevo?» en una pregunta más difícil de lo que parece: 7.1.6 sí ordena por encima de 6.1.13, pero pasar de una a otra es una compra aparte, y CCC 7 necesita un macOS más nuevo del que puede que esté corriendo una máquina con CCC 5. Responder solo por el número de versión le habría dicho a cada propietario de CCC 5 y 6 que había una actualización gratuita esperando, para siempre, y se habría equivocado cada vez. Así que DuoUpdater lee cada generación desde su propia dirección y solo ofrece nunca la siguiente versión dentro de la generación que realmente tienes. Las versiones beta también se recogen, para quien las haya activado dentro de CCC. Por ahora solo detección — CCC instala un helper con privilegios junto a la app, lo cual es una promesa mayor que las actualizaciones con un clic que ya hay aquí — y el motivo por el que nada podía ver antes estas actualizaciones merece quedar registrado: el propio feed de actualización de la app responde con éxito a cada solicitud, con una página completamente vacía.

**Una actualización que tu Mac en realidad no puede ejecutar ya no se descarga ni se instala.** Cada bundle de app declara el macOS más antiguo en el que arrancará, y algunos proveedores también declaran el más nuevo — «este build no es para un sistema operativo tan reciente», que es la forma en que una app que no se ha puesto al día con macOS 27 lo dice. DuoUpdater no leía ninguno de los dos. En las apps rastreadas mediante un feed de Sparkle el suelo ya se respetaba, pero esas son una minoría: de las apps en una Mac típica, las que se leen desde el propio endpoint de un proveedor o desde GitHub releases son la mitad mayor, y un release de GitHub no publica ningún requisito de macOS en ninguna parte. Así que una app que ya había avanzado a un macOS más nuevo que el tuyo podía ofrecerse, descargarse por completo, instalarse — y luego no abrir. DuoUpdater ahora lee el requisito directamente de la app descargada, justo al lado de la comprobación que ya existía de que está compilada para tu procesador, y rechaza el intercambio en lugar de reemplazar una copia que funciona por una que no va a arrancar. El límite superior que declara el proveedor también se respeta, donde un feed publica uno, así que un build que el desarrollador ha marcado como no apto para tu macOS no se ofrece en primer lugar. Tres límites que merece la pena decir con claridad. Leer el requisito a partir de la descarga significa que la descarga ya ha ocurrido — esto evita una instalación rota, no el tráfico, porque para la mayoría de las apps no hay ningún sitio anterior donde preguntar. Una app cuya versión más nueva tu Mac no puede ejecutar seguirá mostrando esa actualización y seguirá negándose a instalarla; el rechazo ahora nombra la versión de macOS que exige, pero DuoUpdater todavía no recuerda la respuesta ni deja de ofrecerla. Y la comprobación cubre las rutas en las que DuoUpdater intercambia el propio bundle de la app — un paquete instalador le entrega el archivo a macOS, que impone los propios requisitos del paquete, y Homebrew y la App Store eligen sus propios builds; las apps que vienen de la sección de iPhone y iPad de la App Store se saltan deliberadamente, ya que la versión que declaran es una versión de iOS y compararla contra macOS sería peor que no comprobar nada. Una cosa que todavía no dice en voz alta: cuando un desarrollador ha marcado un build como no apto para tu macOS, esa actualización simplemente no se ofrece, y la app se lee como al día en lugar de explicar por qué. Para una Mac más antigua eso se resuelve solo el día que actualices macOS. Para una Mac demasiado nueva no se resuelve, y ahí se debe una respuesta mejor que el silencio.

## 0.3.71

**百度网盘 ahora está bajo seguimiento: nuevas versiones, actualizaciones con un clic y sus notas de versión en la ventana.** Ninguna de las rutas habituales estaba disponible. No publica un feed de Sparkle; la cask de Homebrew no puede informar sobre una copia instalada manualmente; y el manifest de actualización al que el nombre de su propio bundle apunta está caído (ese archivo, su gemelo arm64 y el directorio que los contiene responden con 404). Así que DuoUpdater lee el endpoint desde el que se construye la propia página de descarga del proveedor, e instala la imagen de disco arm64 notarizada mencionada en esa misma respuesta. Sus notas de versión llegan del mismo modo: la página «版本更新» tiene una pestaña Mac版, pero la página en sí se envía vacía y se rellena desde una API, por lo que DuoUpdater lee esa API directamente y renderiza las últimas cuarenta versiones en su propia ventana. Un límite que merece la pena destacar claramente: ese feed publica la versión que se te muestra y nunca el número de build que hay debajo, así que un nuevo corte de una versión que mantiene su nombre es invisible aquí. No puede inventar una actualización que no existe; simplemente no puede ver ese tipo.

**Una comprobación que falló ahora dice que falló, en lugar de mostrar un espacio en blanco.** Una app cuya versión solo el propio endpoint de un proveedor puede responder tenía una forma de decir «sin respuesta»: un guión vacío, que es también lo que se ve cuando no hay nada que DuoUpdater siga. Así que un endpoint de un proveedor agotado o movido se leía exactamente como «DuoUpdater no sigue esta app»: un veredicto de aspecto permanente, sin botón Reintentar y sin nada en el recuento de «apps que no se pudieron comprobar». Ahora son una comprobación fallida, que es lo que son: un botón Reintentar, un lugar en el recuento, y la razón nombrada. Deliberadamente no todo: una condición que tu Mac simplemente no puede hacer nada al respecto (sin receta para la pista de versión que tienes, un endpoint que necesita una identidad que esta máquina no tiene) se mantiene como el guión tranquilo que siempre fue, y una comprobación que ha fallado tres rondas seguidas sigue saliendo del banner en lugar de mantenerlo para siempre. Una app que JetBrains Toolbox instala también conserva su botón «abrir Toolbox» cuando la lectura de la versión detrás de él falla, ya que abrir Toolbox era la respuesta de todos modos.

**El recordatorio «reabrir para aplicarlo» ahora desaparece una vez que has reabierto.** Cuando el propio actualizador de una app descargó un build en segundo plano, DuoUpdater te lo dijo y ofreció un botón Reabrir en la notificación. Usarlo funcionó: la app volvió en el nuevo build y dijo «Ahora se está ejecutando 1.0.»; pero el recordatorio que reemplazó se quedó en el Centro de notificaciones debajo, aún pidiéndote que reabreras algo que acababas de reabrir. DuoUpdater estaba esperando el recordatorio para *dejar de* ser relevante, y el momento en que comprobó fue el único momento que ya había sido contabilizado. Ahora quita el recordatorio siempre que no hay un reabrir pendiente, lo que también limpia uno dejado atrás por una app que aplicó su propia actualización mientras DuoUpdater no estaba ejecutándose.

## 0.3.70

**Las apps que envían muchos builds bajo un número de versión ahora se manejan correctamente, en todas partes.** Una app de Mac lleva dos strings de versión: la que te muestra («1.0») y un número de build que realmente cuenta hacia arriba. La mayoría de las apps mueven ambos. Algunas mueven solo el build: Amp envió diez builds en un solo día, todos ellos llamados 1.0; Surge ha enviado cuatro versiones separadas como 6.9.0; los preview builds de JetBrains hacen lo mismo. DuoUpdater decidió «¿ha cambiado esto?» comparando la versión *mostrada* en aproximadamente una docena de lugares, y para esas apps esa comparación solo puede responder «no», o donde preguntó «¿son estos iguales?», «sí». Lo que sigue es lo que eso rompió. Es un error, encontrado porque Amp lo hizo visible.

**Reabrir ya no parece colgarse durante tres minutos y luego reportar un fallo que no sucedió.** Hacer clic en Reabrir en una app cuyo propio actualizador tenía un build esperando giraba durante tres minutos y luego decía que había fallado, mientras que la actualización en realidad se había aplicado en un segundo o dos y la app ya había reabierto en el nuevo build. DuoUpdater estaba observando la versión mostrada para un cambio que nunca iba a venir. Medido en Amp: 189 segundos de spinner para un intercambio que tardó menos de uno. Ahora se resuelve en mucho menos de un segundo, y un fallo real sigue siendo reportado como uno.

**Reabrir ya no te ofrece un build que ya está desactualizado.** Cuando el actualizador de una app había descargado un build y el desarrollador desde entonces publicó otro, DuoUpdater aún ofrecía Reabrir, así que reabría y de inmediato te quedabas con un build atrasado, que es exactamente lo que esa comprobación fue escrita para prevenir. Esas filas ahora ofrecen **Actualizar** en su lugar, que obtiene el build actual.

**Omitir una versión ya no silencia una app para siempre.** «Omitir esta versión» está destinado a declinar una versión y dejar pasar la siguiente. Solo registraba la versión mostrada, así que para una app que mantiene un nombre de versión entre builds, omitir una vez declinaba *cada* versión futura; permanentemente, sobreviviendo reinicios, sin nada en la pantalla para decir que la app había quedado silenciosa. Una omisión ahora registra el build que declinó. Una consecuencia de la reparación: una versión omitida por un DuoUpdater anterior se te ofrece una vez más, porque el registro antiguo no puede decir qué build significaba. Omitirlo de nuevo lo registra correctamente.

**La reversión vuelve para actualizaciones que parecían no cambiar nada.** El workbench oculta una reversión que no haría nada, y para estas apps cada reversión parecía no hacer nada, así que la fila desaparecía después de una actualización genuina mientras una copia de seguridad completa estaba en el disco sin forma de alcanzarla.

**El recordatorio de reabrir se anuncia una vez por build de nuevo, y sobrevive al desarrollador enviando otro.** La versión 0.3.69 reemplazó un recordatorio que se repetía cada cinco minutos por uno que habla una vez por build preparado; pero identificó el build por su nombre, así que para estas apps anunció el primero y luego se quedó en silencio para cada uno después. Eso está arreglado. Por separado: si una app se niega a cerrarse porque tiene trabajo sin guardar, DuoUpdater mantiene una nota para volver a abrirla una vez que hayas respondido. Esa nota solía ser descartada si el desarrollador publicaba otro build mientras decidías, dejando la app cerrada después del intercambio sin nada que la volviese a abrir. Ahora sigue el nuevo build en su lugar.

**Una actualización fallida de App Store ya no se registra silenciosamente como un éxito**, y un paquete instalador descargado ya no se trata como el que actualmente se ofrece cuando es un build más antiguo. Ambos vinieron de la misma comparación. El historial de versiones también contaba diez builds de una app como una versión; ahora los cuenta por separado, aunque el historial ya registrado no puede recuperarse.

**La fila misma dice qué build instalará un reabrir.** Decía «1.0 → 1.0»: una línea que no nombraba ninguna diferencia en absoluto. Ahora dice «1.0 (129) → 1.0 (130)», y solo cuando el build es lo que cambió; donde los nombres de versión ya difieren, la línea es sin cambios. La misma corrección llega a los tooltips de Reabrir, la notificación, la nota que explica por qué se pospuso una instalación, y la negativa de `duo install`.

## 0.3.69

**微信输入法 y 豆包输入法 pueden actualizarse con un clic de nuevo, y se actualizan de la manera en que se actualizan a sí mismas.** Un clic para métodos de entrada fue retirado en la versión 0.3.25 el día que se envió, después de que la configuración de método de entrada de alguien desapareciera. Lo que estaba mal con eso era la forma de la instalación: reemplazó la app completa, de la manera que hace un instalador de primera vez. Un método de entrada está registrado con macOS por la *ubicación* de su app, y ambas de estas apps se actualizan a sí mismas sin tocar esa ubicación; mantienen la app e intercambian lo que hay dentro. DuoUpdater ahora hace lo mismo, así que la app registrada viene a través de una actualización como la misma app, y un fallo en cualquier punto deja la copia que estabas ejecutando exactamente donde estaba. Tampoco ninguno de los dos vuelve a pedirte la contraseña.

**Antes de que se actualice cualquiera de ellos, todo lo que han aprendido se copia primero.** Tu diccionario, tu configuración y tu estado de cuenta no viven dentro de la app, así que la copia de reversión que DuoUpdater ya mantenía no podía hablar por ellos. Ahora se capturan en una instantánea antes de cada actualización de método de entrada y se restauran junto con la reversión, y la copia sale casi gratis: 578 MB de uno de ellos toma una décima de segundo y casi nada de disco. Esta es una red de seguridad en lugar de una reparación: lo que una app decide hacer con tus datos la próxima vez que comienza es el código de la app ejecutándose, y nada puede estar frente a eso. Ahora hay algo a lo que volver.

**Una actualización ya no quita silenciosamente la capacidad de una app de actualizarse a sí misma.** Cuando DuoUpdater necesitaba un administrador para reemplazar una app, restauraba quién era el propietario de la app pero no los permisos con los que fue instalada; y una descarga normalmente desempaqueta con permisos más estrechos que un instalador establece. Para ambos métodos de entrada esa es la diferencia entre su propio actualizador poder terminar su próxima actualización y no poder limpiar después de sí mismo. Los permisos con los que se instaló una app ahora se llevan a la copia que la reemplaza.

**DuoUpdater deja de pedirte que reabras la misma app cada cinco minutos.** Una app que se actualiza a sí misma estaciona la nueva versión en el disco y espera a que la cierres. DuoUpdater lo notó en cada comprobación y publicó un recordatorio cada vez, así que un build que habías decidido no reabrir aún seguía molestándote mientras lo dejaras. Cada build ahora se anuncia una vez: reábrelo, omítelo, o ignora la app y se queda en silencio, y el próximo build se anuncia normalmente.

**Una app esperando ser reabierta cuenta como una actualización, y una ignorada ya no cuenta en absoluto.** Una nueva versión ya en el disco *es* una actualización; simplemente se descargó temprano; así que ahora se cuenta en el badge y en la línea «N actualizaciones disponibles» en lugar de en un recuento separado junto a ellos. Las apps ignoradas fueron al otro lado: una que habías ignorado podía encender el badge mientras su fila mostraba una etiqueta «Ignoradas» silenciada y sin botón para presionar, así que el número apuntaba a algo sobre lo que no podías actuar. Ignorar y omitir ahora significan lo mismo en las tres superficies: el recordatorio, el badge y la lista.

**搜狗输入法 ahora está bajo seguimiento, pidiendo a su propio actualizador en lugar de leer su sitio web.** El changelog de Sogou publica números de versión de tres segmentos donde la copia instalada lleva cuatro, así que compararla habría significado recortar la versión real primero. Su propio chequeo de actualización responde en la numeración propia del bundle en su lugar. DuoUpdater pregunta ese endpoint de la manera en que lo hace la app y lee la versión de ello, todos los cuatro segmentos, así que un respin que cambia solo el último es visible. Este es solo detección: el actualizador de Sogou hace mucho más que intercambiar la app; re-registra un generador de QuickLook, mueve tu información a una nueva ubicación y fuerza el cierre del método de entrada; así que la actualización en sí se deja en sus manos. Una cosa que merece la pena saber, y es culpa de Sogou más que la nuestra: su endpoint responde según la versión de macOS que pregunta, y una Mac en macOS 28 pidiéndose a sí misma recibe un build de 2023. DuoUpdater no se pide a sí mismo, así que la versión que te muestra es la actual en cada Mac.

**Las notas de versión que una corrección posterior habría obtenido bien se leen de nuevo, en lugar de permanecer mal para siempre.** Las notas se cachean por versión, bajo la razón de que las notas de una versión lanzada nunca cambian. Eso es cierto de las notas y no de lo que DuoUpdater logra extraer de ellas, así que una app cuyas notas salieron confusas quedaba así para esa versión sin importar cuántas correcciones de análisis se enviasen después. Cada entrada en caché ahora registra qué generación de la lógica de extracción la escribió, y una escrita por una generación anterior se obtiene de nuevo. Ambos cachés hacen esto: changelogs de app, y notas de fórmula de Homebrew.

**Un chequeo que falla en la CDN de alguien se pide una vez más antes de contar como roto.** 502, 503 y 504 todos significan que un intermediario no pudo alcanzar el servidor detrás: la solicitud nunca llegó, así que la misma solicitud un momento después rutinariamente funciona. La comprobación de Headlamp murió en exactamente eso: GitHub respondió 504 sin encabezado de límite de velocidad en absoluto. Esos tres ahora obtienen un reintento, después de ocho décimas de segundo. Deliberadamente solo esos tres: un 500 es el propio servidor fallando y repetirlo principalmente lo reproduce, y reintentar un límite de velocidad gasta el presupuesto del que se está quejando.

**Las notas de versión de una fórmula de Homebrew siguen la versión a la que pertenecen.** Las notas se recordaban por fórmula y nunca por versión, así que una vez que las notas de una fórmula se habían cargado, cada mirada posterior recibía las notas de la primera versión para el resto de la sesión; incluyendo después de que apareciera una versión más nueva. Leerlas también solía ocupar la cola en la que esperaba el resto de la lista de fórmulas, así que un lento `brew info` podría atascar la lista a su alrededor.

**Haz clic derecho en una app en la barra lateral del workbench para abrirla.** El mismo Abrir que las filas de la barra de menú siempre han ofrecido, en la ventana donde es más probable que lo quieras.

**Descartar un instalador descargado lleva consigo el error que dejó atrás.** Tirar un paquete preparado ya ponía la fila de vuelta a Actualizar, pero un fracaso rojo del intento que acababas de cancelar se quedó sentado; y nada lo habría limpiado nunca, ya que un error solo se retira una vez que una fila ha estado actualizada, lo que una fila que aún ofrece una actualización nunca hace. Va con la descarga ahora.

**`duo`, el acompañante opcional de línea de comandos, deja de describirse a sí mismo de manera inexacta.** `--timeout` se ha ido: se aceptaba, se documentaba, y lo leía nada. `--budget` se documenta por primera vez, y el único mensaje que lo menciona ahora dice un número real de minutos en lugar de siempre «15». `--max-calls` reclamaba un predeterminado de 20 cuando es 6. Un flag numérico entregado algo que no es un número es ahora un error: `duo verify --max-concurrency 1x` solía ser ignorado y sustituido en silencio por el valor predeterminado de cuatro, justo lo contrario de lo que querría alguien que ralentiza un barrido a propósito. Y `duo verify` cuenta las solicitudes que realmente hizo: un feed que responde 502 y tiene éxito en el reintento ya no reporta un limpio `ok` mientras silenciosamente pregunta dos veces. `-h` funciona en todos los sitios en que `--help` funciona.

## 0.3.68

**Cuatro apps más se rastrean, dos canales de versión más, y cada uno de ellos se actualiza en su lugar.** CapCut, Canva, y WorkBuddy en ambos de los sitios en que se envía; la internacional y la versión china ejecutan trenes de versión independientes, así que una instalación solo se ofrece nunca la versión y las notas pertenecientes a su propio sitio. Termius y VSCodium obtienen sus canales Beta e Insiders junto a los builds estables ya cubiertos. El segundo track de CapCut es el incómodo: es elegido por un interruptor dentro de CapCut mismo y no aparece en ninguna parte del número de versión, así que el track en el que te encuentras se lee de la copia en el disco, en lugar de adivinarse a partir del build que resulte estar ejecutando. Merece la pena saber si marcas esa casilla: DuoUpdater te ofrecerá el beta más nuevo tan pronto como exista, que puede estar por delante del punto en que el lanzamiento escalonado de CapCut te habría alcanzado.

**Los canales preview de Android Studio ya no te ofrecen un build más antiguo que el que tienes.** Google lista sus versiones en el orden en que fueron publicadas en lugar de por versión, y DuoUpdater buscaba esa lista tres veces separadas: una por la versión, una por la fecha, una por la descarga; así que un candidato de versión publicado después de un canario más nuevo podría suministrar la versión de una entrada y el archivo de otro. El 26 de agosto el canal Canary respondió con 2026.1.4 RC 2 mientras 2026.2.1 Canary 2 ya se había enviado. Cada una de esas respuestas ahora tiene que venir de la misma entrada.

**Un relanzamiento que no cambia de versión ya no instala la copia que se suponía que reemplazaba.** Cuando un proyecto reconstruye una versión sin cambiar su versión, ambos archivos se quedan bajo la única etiqueta: KeePassXC envía `KeePassXC-2.7.11-1-arm64.dmg` al lado del original `KeePassXC-2.7.11-arm64.dmg`; y DuoUpdater tomó cualquiera que fuera listado primero. Ese orden es alfabético: esta vez colocó la reconstrucción primero, y la próxima vez la habría colocado última. Nada al respecto era visible: la versión en la fila era correcta, solo el archivo detrás era incorrecto. El correcto ahora se elige por lo que el nombre de archivo en sí dice.

**Las compilaciones Nightly y snapshot se reconocen como los pre-releases que son.** El nightly de VLC, el snapshot de KeePassXC y el nightly de Freelens todos se instalan bajo el nombre de la app estable e identificador de bundle, así que su string de versión es la única cosa que los delata; y no se estaba leyendo. Contaban como instalaciones estables, que es cómo un nightly termina siendo ofrecido una versión ordinaria para sobrescribirse a sí misma. El nightly de DB Browser for SQLite se lee del propio nombre de archivo de la app por la misma razón, y allí el problema estaba vivo pero oculto: su versión congelada ordena por encima de la estable actual solo hasta que la estable se ponga al día, momento en el que cada instalación nightly habría recibido silenciosamente una compilación estable.

**Reabrir una app reporta lo que realmente sucedió.** Algunas apps envían una segunda app dentro de su propio bundle: Surge mantiene su Dashboard allí; y cuando solo esa app interna necesitaba reiniciar, DuoUpdater decía que la app externa se había reabierto, cuando en realidad no se había reabierto nada. Ahora reporta el resultado propio de la app interna, y ya no genera una notificación de reabrir para un reabrir que nunca sucedió.

**Una actualización que ya ha descargado lo dice, y puede ponerse de vuelta.** Una fila sosteniendo un paquete instalador que había terminado de descargar mostraba un botón Instalar azul y nada más; nada dijo que la descarga ya estaba hecha, o que el botón reabre el instalador en lugar de comenzar la actualización de nuevo, y no había forma de cambiar de idea. Eso ahora está en la fila misma en lugar de ocultado en un tooltip, y **Descartar el instalador descargado** en el menú de clic derecho de la fila tira la descarga y pone la fila de vuelta a Actualizar. Descartar uno mientras una instalación de la misma app ya estaba en ejecución también podría tirar un paquete que acababa de terminar de descargar; ya no puede.

**Los botones de notas de versión que apuntaban a páginas retiradas abren los vivos de nuevo.** Microsoft renombró las páginas de notas de versión empresariales de Edge y Termius movió su changelog, así que tres canales de Edge y Termius te estaban enviando a una página que ya no existía. Nada había comprobado nunca si esas páginas aún estaban allí, que es por qué podían pudrirse indefinidamente con todo lo demás viéndose saludable: ahora se comprueban en un horario. El canal Dev de Edge no obtiene botón en absoluto: Microsoft dejó de publicar notas para ello, y cada página que aún existe pertenece a un tren de versión diferente.

**Raycast es seguido a la versión 2, y solo en los Macs que pueden ejecutarla.** Raycast 2 necesita macOS Tahoe y silicio de Apple. Una Mac que no cumple eso se queda en el tren de versión 1 y ya no se le dice sobre una versión que nunca habría podido instalar. Los dos trenes también mantienen sus propias notas de versión ahora, así que una instalación de versión 1 lee el historial de la versión 1 en lugar del de la versión 2.

**Las notas de versión se renderizan en la propia ventana de DuoUpdater para más apps.** BetterDisplay en todos sus tres tracks, Shotbase, y WorkBuddy en ambos sitios. Las notas de BetterDisplay ya no terminan en el markup crudo de su botón de descarga, y ya no repiten su lista de contribuyentes en cada versión.

**`duo`, el acompañante opcional de línea de comandos, rechaza una línea de comandos que no entiende.** Un flag mal escrito solía ser ignorado, y un flag ignorado se lee como uno que nunca pasaste; así que `duo verify --githubb` silenciosamente verificaba cada receta en lugar de la que pediste. Los flags desconocidos, un flag dejado sin su valor, y argumentos extraños ahora son errores que nombran lo que el comando realmente acepta, y `--help` funciona después de cualquier comando.

## 0.3.67

**Los builds de pre-release e internos de BetterDisplay ahora se ofrecen a las personas que los pidieron.** BetterDisplay lleva sus tres trenes de versión en un único feed de actualización y elige entre ellos con dos interruptores en su propia configuración. DuoUpdater solo podía adivinar tu tren del build que sucedía estar ejecutando, que no dice nada sobre un interruptor que activaste pero aún no has actuado; así que alguien con ambos interruptores activados, sentándose en un build estable, se le dijo que estaba actualizado mientras el propio actualizador de BetterDisplay ofrecía una versión cuatro versiones adelante. Tu verdadera elección ahora se lee de BetterDisplay, incluido el caso en el que activar los builds internos también sigue trayendo las pre-releases ordinarias. Sus builds preview de solo silicio de Apple se dejan deliberadamente fuera, así que una Mac Intel nunca se ofrece una que no puede ejecutar.

**Cambiar el canal de versión de una app dos veces seguidas ya no queda la fila en la respuesta anterior.** Voltear un interruptor de canal envía DuoUpdater a re-comprobar esa app, y un segundo volteo mientras el primer chequeo aún estaba en ejecución solía descartarse; la fila continuaba ofreciendo un beta a alguien que acababa de apagar los betas, hasta que algo no relacionado sucedía para activar otra comprobación. El volteo más nuevo ahora toma el lugar del más antiguo, y un chequeo que es interrumpido a mitad de camino deja las apps que nunca alcanzó marcadas para el próximo paso en lugar de registrarse como manejadas. Las filas también entran en su estado de comprobación más pronto después de un volteo, así que hay menos tiempo en el que la respuesta en pantalla es una que tu interruptor ya ha invalidado.

## 0.3.66

**Una app que vive dentro de otra app ahora se cierra y reabre junto con ella.** Algunas apps envían una segunda app completa dentro de su propio bundle: Surge mantiene su Dashboard allí. macOS lo trata como una app separada, así que nada la cerró cuando se aplicó una actualización a la app alrededor: continuó ejecutando la versión que acababa de ser reemplazada, fuera de una copia que ya no estaba donde pensaba que estaba, y desde allí no podía hablar con la app a la que pertenece. Ahora se cierran con la app en que viven y se reabren después, y cualquiera sea la ventana en la que realmente estabas trabajando es la que vuelve al frente. Solo las apps que podrías haber abierto tú mismo son tratadas de esta manera; los procesos auxiliares invisibles que una app ejecuta para sí misma se dejan solos.

**Los puntos de reversión que silenciosamente habían dejado de ser tomados están siendo tomados de nuevo.** Una app puede bloquear uno de sus propios archivos para que nada pueda borrarlo, y la copia mantenida para reversión heredó ese bloqueo; así que nunca podría ser reemplazada por la próxima, y un único intento interrumpido podría dejar una copia que nada fue capaz de limpiar. Después de eso, cada actualización de esa app siguió adelante sin forma de regresar, y lo dijo en una línea que no dio razón. Una app en la propia Mac del desarrollador había estado en ese estado durante dos días. Las copias mantenidas para reversión ya no llevan el bloqueo, la app instalada se deja exactamente como su desarrollador la configuró, y una copia que ha quedado atrapada ya no puede bloquear la destinada a reemplazarla.

**Una actualización que funcionó ya no reporta que falló.** macOS puede poner una nueva versión en su lugar y luego fallar mientras elimina la que desplazó. Eso fue tomado al pie de la letra: DuoUpdater diría que una app no había sido actualizada cuando lo había sido, o que no había punto de reversión mientras uno completo estaba sentado en la tienda de copia de seguridad; y en el primer caso te enviaba a conceder un permiso que ya habías concedido y que no habría podido ayudar de todos modos. Lo que realmente sucedió en el disco ahora se verifica antes de que nada sea reportado.

**Las líneas de versión ya no repiten dígitos que el número de versión ya contiene.** Cuando una app espera ser reabierta, la fila muestra la versión que estás ejecutando y la que un reabrir aterrizará. Ambos lados llevaban un número de build, que es lo que hace la diferencia legible cuando un desarrollador envía varios builds bajo un nombre de versión: y puro ruido cuando las versiones ya difieren. La línea de Chrome gastó su ancho imprimiendo «151.0.7922.174 (7922.17…» y se quedó sin los dígitos que realmente cambiaron. Los números de build ahora aparecen solo cuando son lo que cambió.

## 0.3.65

**Una palabra ahora para reabrir una app y terminar su actualización.** Una app cuyo propio actualizador ya había puesto la nueva versión en su sitio te pedía «Reiniciar»; una que guarda la nueva versión aparte hasta que cierras te pedía «Reabrir». Esa diferencia era real tras bambalinas y no cambiaba nada para ti: el mismo clic de cualquier forma, y el mismo resultado si nunca hacías clic, ya que la actualización se aplica la próxima vez que cierras la app de todos modos. Ahora en todas partes se lee Reabrir: en las notificaciones, en los tooltips y en el ajuste que lo hace por ti; que es también la palabra que Chrome, Claude y la mayoría de las apps que se actualizan solas te muestran. Solo el inglés llegó a tener dos palabras para esto; el alemán, el japonés, el ruso y el chino siempre han usado una sola, y el español y el francés pasan a usar la palabra que ya empleaban en otros lugares.

## 0.3.64

**Una actualización que necesita un administrador ahora pide uno, en lugar de fallar y culpar a un permiso.** Si un intercambio necesitaba una contraseña se decidía mirando la carpeta en la que se sienta una app en lugar de la app misma. Cualquier cosa que macOS instaló como root —cada app de App Store, y cualquier app que dejó puesta un paquete instalador— pasaba esa prueba, tomaba la ruta que no necesita contraseña, y no podía terminar de ningún modo: eliminar la versión anterior requiere acceso de escritura a los directorios que contiene. macOS reporta esa negación con el mismo código que usa para un permiso de Gestión de apps denegado, así que el fracaso llegaba como una solicitud para conceder Gestión de apps, que nunca podía ayudar, porque el obstáculo era la propiedad de los archivos. En una Mac corriente eso abarcaba cada app de App Store y un puñado de otras además, y eran las cuentas de administrador las afectadas; las cuentas estándar ya se estaban encaminando correctamente. Esas actualizaciones ahora toman la ruta que funciona, y la app conserva el propietario que tenía en lugar de convertirse silenciosamente en tuyo.

**Las apps de App Store ahora obtienen un punto de reversión como todo lo demás.** Las copias de seguridad las saltaban, sobre el razonamiento de que la tienda siempre puede obtener una compilación anterior de vuelta. No puede; la App Store ofrece solo la versión actual de una app; que dejó a la tienda como la única ruta que aplicó una actualización sin forma de deshacer. Esas apps ahora son respaldadas antes de una actualización como cualquier otra, y porque la copia se hace clonándola cuesta casi ningún espacio de disco hasta que la actualización realmente reemplaza el original. Restaurar una de ellas indica lo que es específico de la tienda: la actualización reaparece en la lista de Actualizaciones de inmediato, y se re-aplica por su cuenta si las actualizaciones automáticas de apps están activadas. Y cuando una actualización de la tienda nunca iba a aplicarse: una app de iPhone ejecutándose en una Mac, un título no vendido en tu región; no se toma ningún punto de reversión, así que una fila ya no puede ofrecer revertir a la versión que ya está ejecutando.

**Longbridge Desktop ahora se rastrea, en ambos de sus trenes de versión.** Estable y Vista previa cada uno obtienen detección de versión, instalación con un clic de la compilación de silicio de Apple oficial, y notas de versión renderizadas en la propia ventana de DuoUpdater, ilustraciones incluidas.

**Las notas de versión de WhatsApp ahora aparecen mientras su comprobación de App Store aún está en ejecución.** La página de App Store mostrada en esa ventana se había archivado bajo un nombre que la búsqueda nunca podía coincidir, así que el panel de notas estaba vacío en lugar de mostrarlo.

**El encabezado de menú lleva más en menos espacio.** La versión de DuoUpdater ahora se sienta junto a su nombre, y al hacer clic se abren sus notas de versión. «Actualizar todo» se ha trasladado a su propia línea, donde una etiqueta traducida tiene espacio para ser leída en su totalidad, y las acciones a lo largo de la parte inferior son iconos. El banner que solía anunciar DuoUpdater actualizándose a sí mismo se ha ido: el brillo junto a la versión se enciende en su lugar, y permanece encendido hasta que hayas leído qué cambió. Una línea de estado demasiado larga para el menú ahora termina en puntos suspensivos en lugar de estirarla.

**Ajustes ya no acorta las opciones de actualización que está ofreciendo.** Los dos menús que deciden cómo se aplica una actualización estaban recortando sus propias etiquetas en varios idiomas. La redacción es más corta ahora, y se trasladan a una segunda línea donde las palabras aún la necesitan.

**Novedades dice cuándo se envió cada versión.** Cada versión en el carril ahora lleva su fecha de publicación.

## 0.3.63

**Las actualizaciones específicas de arquitectura ahora eligen el build que este Mac puede ejecutar.** Algunas apps publican la misma versión dos veces en un feed de Sparkle: una vez para silicio de Apple y una vez para Intel; y DuoUpdater solía resolver ese empate quedándose con la dirección de descarga que diera la casualidad de aparecer primera al ordenarlas. Ahora lee el requisito de hardware del feed y, donde un proveedor deja eso en blanco, la arquitectura en el nombre de archivo. El build nativo gana consistentemente, y un build que esta Mac no puede lanzar no se ofrece. Los lanzamientos de GitHub obtienen el mismo tratamiento, sin llamar a una receta perfectamente saludable rota solo porque su artefacto más nuevo apunta a otra arquitectura.

**Las comprobaciones de actualización de ChatGPT ahora siguen la pista de rollout unida a la cuenta.** OpenAI a veces mantiene cuentas comerciales y empresariales en un build de escritorio anterior mientras uno más nuevo llega primero a cuentas de consumidor. DuoUpdater solía omitir el plan de la cuenta de esa comprobación, que silenciosamente seleccionaba la pista cautelosa para todos: podía decir que la copia instalada estaba, de alguna manera, por delante, mientras ChatGPT mismo ya estaba descargando un build más nuevo, u ofrecer un build que el propio actualizador de la app reemplazaría de nuevo. Ahora envía la etiqueta de plan desde el estado de inicio de sesión de ChatGPT/Codex con la misma solicitud de actualización que hace la app. Si esa etiqueta no está disponible mantiene el comportamiento cauteloso; las credenciales en sí nunca se ponen en la solicitud o diagnósticos.

**Un reabrir que macOS nunca puede responder ya no puede cuñar cada actualización posterior.** Servicios de lanzamiento ocasionalmente aceptan una solicitud para reabrir una app actualizada y luego nunca devuelven la llamada. La fila se quedó en «Reabriendo…» para siempre, su botón Reiniciar permaneció deshabilitado, y la actualización de DuoUpdater mismo esperó detrás. Un lanzamiento que no ha respondido después de un minuto ahora se libera como fallido, así que la fila se recupera y el resto del actualizador sigue funcionando.

**Release Log permanece poblado cuando su barra de desplazamiento se arrastra rápidamente.** La pila perezosa anterior podía ser superada por un largo salto, dejando brevemente una ventana en blanco mientras las filas se creaban alrededor de la nueva posición. El registro ahora usa una lista de reciclaje que puede saltar directamente al destino. El control de actualización también mantiene la misma huella mientras cambia entre su flecha y spinner, así que la fila inferior ya no se retuerce cuando comienza una comprobación.

**Download Traffic ahora marca actualizaciones que usaron un parche binario.** Las nuevas descargas registran la ruta que realmente completó; no meramente si se ofreció un parche; y llevan un badge Delta en su historial. Las descargas de parche, inconfundiblemente más pequeñas, de 0.3.62 también se reconocen, aunque se registraron antes de que el libro mayor de tráfico tuviera un campo de ruta.

## 0.3.62

**Las actualizaciones ahora descargan solo lo que cambió, cuando el desarrollador lo publica de esa manera.** Algunas apps envían un pequeño parche junto con cada versión; lo suficiente para convertir la versión que tienes en la nueva, sin obtener toda nuevamente. DuoUpdater solía ignorarlos y descargar el paquete completo cada vez. Ahora lo toma cuando uno coincide con el build exacto en que estás. La última actualización de ChatGPT vino a 1.9 MB en lugar de 605 MB; la de Docker a 87 MB en lugar de 582 MB. El resultado es la aplicación idéntica de cualquier forma: misma firma, mismos bytes, verificado contra la descarga completa antes de que esto se enviara. Cuando no hay parche que se ajuste a lo que tienes, o uno falla en aplicarse, la descarga completa sucede como antes, así que nada puede fallar en instalar por esto.

**DuoUpdater ya no descarga una actualización que una app ya está descargando a sí misma.** Muchas apps se actualizan a sí mismas también, y que ambos —DuoUpdater y la app— fueran tras el mismo archivo de 600 MB al mismo tiempo te costaba descargarlo dos veces. DuoUpdater ahora nota una descarga en progreso y la deja sola, diciéndolo en la fila en lugar de no hacer nada silenciosamente. Si esa descarga resulta ser abandonada, deja de contar después de diez minutos así nada se queda bloqueado.

**Una actualización que una app ya ha preparado ya no es sobrescrita.** Las apps que se actualizan a sí mismas a menudo descargan en segundo plano y luego esperan a que las cierres antes de intercambiar la nueva versión. Instalar sobre una de esas parecía funcionar y luego se deshizo en el momento que cerraste la app; y donde la versión pendiente de la propia app era más antigua que lo que DuoUpdater acababa de instalar, terminabas más atrás que cuando comenzaste. Esas actualizaciones ahora se dejan para terminar, cualquier versión que lleven.

**Las actualizaciones de DuoUpdater también se hicieron más pequeñas.** Sus versiones ahora envían el mismo tipo de parche, así que actualizar desde una versión reciente obtiene cientos de kilobytes en lugar de once megabytes.

## 0.3.61

**Las explicaciones dejadas atrás por una actualización ahora se limpian a sí mismas.** Cuando DuoUpdater entrega una app a su propio actualizador, la fila lo dice: «la trajo al frente para que su propio actualizador aplique la actualización». Esa oración solía quedarse ahí para siempre: lo único que la eliminaba era comenzar otra actualización en la misma app, así que aún estaba sentada bajo la fila mucho después de que la actualización hubiera aterrizado, describiendo algo que terminó hace horas. Ahora va tan pronto como la app está actualizada. Una advertencia de que una actualización se aplicó sin un punto de reversión deliberadamente se deja sola, porque describe la actualización que ya sucedió y solo comienza a importar una vez que está acabada.

**Una actualización que fue rechazada ahora se explica a sí misma en tu idioma.** Cuando algo más ya se está instalando: DuoUpdater trabajando a través de un lote, o `duo` en una terminal; la fila te lo dice. Ese mensaje era solo en inglés, en una ventana por lo demás traducida, y terminaba con un número de proceso: útil en una terminal, y nada sobre lo que puedas actuar en un menú. Ahora se traduce, y dice qué hacer en lugar de quién tiene el bloqueo. La herramienta de línea de comandos aún imprime el número de proceso, donde puedes hacer algo con ello.

**La línea del patrón de versión, y su reloj, ahora siguen tu configuración regional.** Release Log → Patterns lo resumió todo como «Most often ships Friday, around 6 PM» («La mayoría de las veces se envía el viernes, alrededor de las 6 PM»). Los idiomas que conjugan los nombres de días no pueden decir eso con el día soltado en el medio de la oración, y obtenían la forma incorrecta de la palabra: el ruso decía «Чаще всего выходит пятница» donde necesita «по пятницам». Ahora es una etiqueta: «Pico: viernes, alrededor de las 6 PM», que es correcta en todas partes. La hora va con ello: si tu Mac escribe horas de reloj en un dial de 24 horas, así lo hace esto, en el eje del gráfico también.

**La búsqueda de Ajustes ahora entiende las palabras en tu pantalla.** El campo de búsqueda anterior a la barra lateral de ajustes coincidía con una lista de términos adicionales que fue escrita en inglés y nunca traducida, así que «rollback» llegaba a General mientras «Zurücksetzen» y «回滚» no llegaban a nada. Esos términos ahora existen en cada idioma que DuoUpdater habla. Los ingleses aún funcionan en cada idioma también, ya que la documentación de la que vienen está en inglés.

## 0.3.60

**Activar «Mostrar todo» ya no hace que el menú titubee.** La lista completa de cada app que tienes fue medida en su totalidad cada vez que apareció; en una Mac con 127 apps llegó a aproximadamente un segundo de trabajo, casi todo gastado en poner las filas muy por debajo de las que puedes ver. Se pagaba en cada alternancia, no solo la primera. Solo las filas realmente en pantalla se construyen ahora.

**Una explicación dejada por una actualización fallida ya no sobrevive al fallo.** Cuando una actualización no pudo ser aplicada; porque algo más ya se estaba instalando, digamos; la fila dijo por qué, en rojo. Nada jamás eliminó esa línea: una vez que la actualización aterrizó y la fila regresó a una marca, la explicación antigua aún estaba sentada debajo, y se quedó allí a través de cada re-comprobación hasta que DuoUpdater se reinició. Ahora se va tan pronto como la app está actualizada. Las razones pertenecientes a actualizaciones que aún están esperando se dejan solas, así que una que aún no hayas leído no puede ser arrasada por una comprobación ejecutándose en segundo plano.

**El botón «Actualizar todo» ya no cambia de tamaño con la duración de la lista.** Con solo unas pocas actualizaciones pendientes, se dibujaba en un tamaño más pequeño del que debería, con ochenta puntos de espacio vacío junto a él, y volvía a su tamaño adecuado cada vez que la lista crecía. Ahora se queda el tamaño que se suponía que debería ser.

## 0.3.59

**Download Traffic ahora dice a qué build una actualización se trasladó, no solo a qué versión.** Muchas apps envían varios builds bajo un nombre de versión: Surge puso cuatro versiones separadas como «6.9.0»; así que esas filas decían «6.9.0 → 6.9.0» y no te decían nada. Ahora dicen «6.9.0 (12028) → 6.9.0 (12030)», y solo cuando el nombre de versión por sí solo no basta; donde la versión ya cambió, el número de build sería solo ruido y se deja fuera.

**El build registrado es el que realmente aterrizó, leído de la app misma una vez que la actualización está en su lugar.** No el número que el feed de actualización del desarrollador anunció; los feeds sí reportan mal, y de esta manera también funciona para los lugares que no publican ningún número de build en absoluto: GitHub, Homebrew y la App Store. Una actualización aún esperando en la ventana del instalador de macOS nunca se adivina; nada se registra para ello hasta que es real.

**Una descarga que no cambió nada ahora se marca como tal.** Ocasionalmente una actualización obtiene e instala el build que ya estaba en tu Mac: un desajuste de número de versión del lado del desarrollador, un espejo sirviendo lo que ya tienes. Eso es ancho de banda real gastado sin resultado, y la ventana de tráfico es donde querrías verlo. Esas filas ahora llevan una etiqueta «sin cambio». Las descargas registradas antes de esta versión no tienen números de build para comparar, así que se dejan solas en lugar de adivinarse: lo desconocido no es lo mismo que lo inalterado.

## 0.3.58

**DuoUpdater ahora te muestra lo que mantener tus apps actualizadas realmente ha costado en descargas.** Ha estado contando, al byte, cada actualización que obtuvo para ti; pero el recuento no tenía dónde aparecer, así que el número se quedó en un archivo que nadie podía leer. Ahora hay una ventana de Download Traffic, abierta desde el botón del gráfico en la parte inferior del menú, con la cifra de este mes impresa junto a ese botón así que la pregunta más común se responde sin abrir nada. Adentro: el total, los últimos tres meses lado a lado con el cambio entre ellos, un desglose de dónde vinieron los bytes, y cada app clasificada por cuánto ha costado: haz clic en una para ver cada actualización que aplicó, de qué versión a cuál, y cuán grande fue esa descarga.

**El total es honesto sobre lo que no puede ver.** Homebrew, la App Store, y apps que se actualizan mediante su propio actualizador integrado obtienen sus propios bytes, y DuoUpdater nunca los maneja; así que la cifra es un piso, no una contabilidad completa. Eso siempre ha sido cierto; lo que cambió es que la ventana lo dice permanentemente, en lugar de solo en la pantalla vacía que ves antes de que nada haya sido registrado.

**Las apps que has renombrado o eliminado desde entonces mantienen su historial.** El tráfico se registra en función de dónde vive una app en el disco, lo que permite que dos canales de la misma app —Android Studio Canary y Beta, digamos— se mantengan separados en lugar de sumarse. El costo es que renombrar una app deja su pasado bajo un nombre que ya no existe. Cuando OpenAI renombró Codex a ChatGPT, eso dividió 30 GB de descargas en dos entradas que parecían duplicados. Esas entradas ahora se agrupan y se oscurecen en la parte inferior de la lista, bajo un encabezado que dice qué son. Nada se tira, y el total aún las incluye.

## 0.3.57

**Una app que instalaste desde la App Store ya no se le ofrece la descarga propia del desarrollador.** Muchas apps se publican en dos lugares a la vez: en la tienda, y como una descarga directa del propio sitio del desarrollador; bajo la misma identidad pero como builds genuinamente diferentes. La descarga directa normalmente va por delante, porque no espera la revisión de la tienda. DuoUpdater verifica la tienda primero para una app de tienda instalada, pero cuando esa comprobación falló por cualquier razón; una conexión soltada, una tienda que no respondió; silenciosamente pasó al sitio del desarrollador y te ofreció lo que había allí. WhatsApp mostró esto como «26.32.75 → 26.33.19»: una versión real, desde el lugar equivocado. Tomarlo habría reemplazado tu copia de tienda con una que la App Store nunca podría actualizar de nuevo. Las apps instaladas desde la tienda ahora se verifican frente a la tienda y en ningún otro lugar.

**Cambiar el canal de actualización de una app dentro de esa app ahora se registra de inmediato.** Algunas apps te permiten elegir entre sus versiones normales y sus beta; Surge, Tailscale, Fork, OrbStack, IINA, Alfred y otros; y DuoUpdater sigue la que hayas elegido, así que nunca te ofrece un build que no pediste. Solía notarlo solo cuando cerrabas la app o abrías una de las ventanas de DuoUpdater. Ninguno cubre lo que la gente realmente hace: apaga la configuración, deja la app en ejecución, y mira la barra de menús. Peor, las apps guardan esa configuración en el disco cuando les conviene en lugar del momento en que haces clic: Surge tardó cinco minutos aquí; así que incluso cerrar podría leerse demasiado temprano. DuoUpdater ahora vigila si la propia configuración cambia y vuelve a comprobar esa app en un segundo o dos. Cambiar Surge de vuelta a versiones normales ahora limpia la versión beta de su fila inmediatamente, en lugar de dejarla allí por hasta una hora.

**Una comprobación que no podría alcanzar nada ya no se ve como un certificado de buena salud limpio.** Cuando cada fuente falló; sin red, o un proxy silenciosamente rechazando conexiones mientras el icono de Wi-Fi aún dice que todo está bien; las apps que fallaron fueron ocultadas y el panel dijo «127 apps · actualizadas». Esa es la misma pantalla que obtienes cuando todo es genuinamente actualizado, que hizo una comprobación fallida indistinguible de una exitosa. El panel ahora dice cuántas apps no pudo alcanzar, muestra qué salió mal, y ofrece intentar esos de nuevo; solo esos, dejando en paz todo lo que sí logró comprobar.
