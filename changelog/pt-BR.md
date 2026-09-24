# Novidades do DuoUpdater

Esta é a tradução para o português do Brasil do arquivo CHANGELOG.md. A versão em inglês prevalece em caso de divergência. Os números de versão que não aparecem aqui são mostrados automaticamente em inglês na janela Novidades.

## 0.4.3

**Os betas e release candidates do Xcode agora são atualizados com um clique.** Inicie sessão uma vez na sua conta Apple Developer em Ajustes → Xcode, e o DuoUpdater baixa e instala os novos betas e RCs como qualquer outra atualização. Antes, ele só conseguia avisar que havia um novo.

**Instale qualquer versão do Xcode ao lado das que você já tem.** Ajustes → Xcode lista todas as versões do Xcode, agrupadas por versão, com o grupo do seu macOS já aberto. Instalar coloca a que você escolher na pasta Aplicativos como uma cópia separada (por exemplo, Xcode-26.6.app) e não substitui nada. Você também pode salvar apenas o arquivo (.xip). Com a sessão iniciada, a própria lista da Apple também é incluída, então as novas versões aparecem em poucos minutos.

**Sua sessão do Apple Developer se renova sozinha.** A Apple encerra uma sessão de desenvolvedor depois de cerca de oito horas. Agora o DuoUpdater obtém uma nova em segundo plano, sem janela e sem senha, enquanto a Apple ainda reconhecer este Mac. Você pode desativar isso em Ajustes → Xcode.

**As novas versões do Xcode aparecem mais cedo.** Nos dias úteis, durante o horário em que a Apple costuma publicar, o DuoUpdater procura um novo Xcode a cada cinco minutos.

**Alguns apps voltaram a funcionar depois que seus desenvolvedores mudaram coisas.** O CapCut beta e o Superconductor nightly voltam a ser encontrados e instalados, e o Superconductor mantém sua identidade de app atual. O VLC 3.0.24 e o JetBrains Air voltam a mostrar suas notas de versão.

## 0.4.2

**O Qoder CN IDE agora é compatível.** A edição do IDE da Qoder para a China continental ganha verificação de atualizações, instalação com um clique e suas notas de versão na janela. O Qoder CN, o app de desktop, agora também mostra suas notas de versão.

**O Qoder IDE não muda mais de ideia sobre qual é a versão mais recente.** A Qoder distribui as atualizações de forma gradual, e agora o DuoUpdater pergunta da mesma forma que a sua cópia do IDE, então recebe sempre a mesma resposta. Antes, a versão oferecida podia alternar entre duas versões, e uma instalação com um clique podia parar no meio porque a resposta mudou.

**Apps com Sparkle que baixaram uma atualização que já ficou desatualizada podem ser atualizados de novo.** Se um app que se atualiza sozinho pelo Sparkle baixou um build e depois saiu um mais novo, o DuoUpdater agora descarta o download antigo e instala o mais recente. Antes, Atualizar continuava dizendo que instalar agora seria desfeito, e a linha nunca mudava.

**O `duo install` avisa quando o build mais recente já está esperando.** Se o próprio atualizador de um app já baixou a versão mais recente, ele agora diz isso e sugere encerrar o app ou executar `duo restart`. Antes, dizia por engano que o app só podia ser verificado, e não instalado.

## 0.4.1

**O 搜狗输入法 agora é atualizado com um clique.** O DuoUpdater aplica a atualização do mesmo jeito que o próprio método de entrada se atualiza — mantendo o pacote instalado no lugar — e antes faz uma cópia do seu dicionário e dos seus ajustes, para que uma reversão também os traga de volta.

**Os backups em outro disco agora preservam o dicionário e os ajustes de um método de entrada.** Antes, só o app em si era movido para o disco de backup, então reverter um método de entrada a partir dali deixava para trás os dados da versão mais nova.

**Chega de atualizações que nunca podem ser instaladas.** O JetBrains Air agora mostra o build que o Toolbox realmente oferece. Um app da App Store que ficou para trás com o nome antigo depois que o desenvolvedor o renomeou agora informa qual cópia a App Store atualiza, em vez de oferecer uma atualização que só reinstala a outra cópia.

**As notas de versão de mais apps aparecem formatadas.** Os apps que publicam suas notas em Markdown agora recebem a mesma lista nativa que todos os outros. Antes, as notas apareciam como texto simples.

## 0.4.0

**Reabrir não concorre mais com o instalador do próprio app.** Quando um app baixou a própria atualização e o backup de reversão dele fica em um disco externo, essa cópia agora espera o instalador terminar. Antes, ela acontecia durante os poucos segundos que o macOS dá ao instalador para fazer o trabalho.

## 0.3.99

**Os backups de reversão agora podem ficar em outro disco.** Um backup é uma cópia inteira de um app, e no disco de inicialização eles se acumulam. Ajustes → Backups lista os discos conectados com o espaço livre de cada um, move os backups que você já tem e grava os novos lá em segundo plano — se você desconectar o disco, terá uma espera, não um ponto de reversão faltando. O `duo backups` ganhou `disks`, `sync`, `verify` e `probe`.

**O 千问输入法 agora é compatível.** O DuoUpdater avisa quando sai uma nova versão e atualiza o método de entrada do mesmo jeito que ele se atualiza sozinho.

**As notas de versão não ficam mais presas na versão anterior.** Quando um desenvolvedor publicava uma atualização alguns minutos antes de a página de histórico de alterações mencioná-la, as notas antigas eram arquivadas sob a versão nova e ficavam lá para sempre. O CleanShot X vinha mostrando as notas da 5.0 sob a 5.0.1 desde o dia do lançamento.

**Apagar um backup agora libera o espaço que diz liberar.** Os backups feitos por versões anteriores do DuoUpdater eram gravados de um jeito que o macOS se recusa a apagar, então Limpar deixava quase toda a cópia no disco e ainda assim a contava como espaço recuperado.

**Limpar abre na hora.** Antes, ele media do zero cada backup guardado toda vez que você clicava.

**O WorkBuddy volta a mostrar sua versão mais recente.** O serviço de atualização dele responde com o próximo passo de uma cadeia de atualizações, e não com o build mais novo, então as quatro edições do WorkBuddy ficavam duas versões atrás.

**Nos bastidores.** Um app que nunca declarou qual binário executa — o Muse, da Meta, entre eles — agora tem seus frameworks e seu SDK lidos mesmo assim.

## 0.3.98

**As atualizações concluídas por Reabrir agora podem ser revertidas.** Quando um app já baixou a própria atualização e você clica em Reabrir, o DuoUpdater agora salva a versão atual antes, então a atualização aparece em Reversão como qualquer outra. Antes, só as atualizações que o próprio DuoUpdater instalava podiam ser desfeitas.

**Veja o que uma atualização mudou dentro de um app.** Para qualquer app com uma versão anterior salva, a bancada agora tem uma visualização Diferenças do Pacote ao lado de Notas de Versão: assinatura e permissões, macOS mínimo, itens de segundo plano e de início de sessão, bibliotecas incluídas e os arquivos que foram adicionados, removidos ou mudaram de tamanho. O `duo diff` faz o mesmo pelo Terminal para quaisquer duas cópias de um app.

**Reabrir avisa quando o próprio atualizador de um app não aplicou a atualização.** Se o app fecha e a atualização nunca chega, a linha agora diz isso e continua oferecendo Reabrir. Antes, o indicador de progresso parava sem dizer nada.

**O Cherry Studio volta a mostrar sua versão mais recente.** Depois que o Cherry Studio renomeou seus downloads para Mac, o DuoUpdater passou a tratar uma versão mais antiga como a mais recente, então as cópias recentes apareciam como “atualizado” e às antigas era oferecido esse build mais antigo.

**As atualizações da App Store não travam mais atrás de um auxiliar que não responde.** Quando o auxiliar do DuoUpdater parava de responder, a atualização ficava em 0% e todas as atualizações da App Store na fila atrás dela esperavam até você encerrar o DuoUpdater.

**Atualizar Tudo não reabre mais apps que você ignorou.** Com “Reabrir apps atualizados automaticamente” ativado, o fim de um lote podia encerrar e reabrir um app ignorado, ou um cuja versão baixada você tinha pulado.

**O Tinycast e o SuperCmd agora são compatíveis.** O DuoUpdater avisa quando sai uma nova versão do Tinycast, ou do beta dele, e agora reconhece o SuperCmd original de código aberto ao lado do SuperCmd 2. As notas de versão do Kimi Code também passam a aparecer.

**As notas de versão correspondem à versão oferecida.** A página de notas de versão mais recente do VS Code aparecia vazia, e logo depois que surgia uma nova versão, o painel de notas podia mostrar a versão anterior.

**O Registro de Versões não adiciona mais a mesma versão a cada abertura.** Apps como Claude, Raycast e Cline ganhavam uma entrada duplicada toda vez que o DuoUpdater era aberto.

**A barra lateral da bancada foi dividida nas abas Apps, Brew e Reversão.** Clique em uma aba ou arraste por elas para alternar; a busca filtra as três ao mesmo tempo.

**Nos bastidores.** Reabrir e Reverter no mesmo app não se atropelam mais; um feed de atualização não consegue mais fazer o DuoUpdater apagar arquivos fora da pasta de downloads dele; as verificações em segundo plano não correm mais o risco de o macOS pedir acesso aos dados de outros apps; um número muito grande no filtro de Requisições não fecha mais o app; e a barra de menus agora respeita um pedido de administrador que você recusou no `duo install`.

## 0.3.97

**As atualizações do iStat Menus são detectadas corretamente.** Quando o iStat Menus relançava uma atualização, o DuoUpdater podia continuar oferecendo-a depois de instalada, e clicar em Atualizar de novo terminava em erro.

**O Memoh Desktop agora é compatível.** O DuoUpdater avisa quando sai uma nova versão e pode atualizá-lo com um clique.

**Atualizar Tudo não pede mais para reabrir um app da App Store que já foi reaberto.** Quando a App Store fecha um app e o reabre na versão nova, a linha dele agora aparece como atualizada na hora, em vez de mostrar “Reabrir agora” até o lote inteiro terminar.

## 0.3.96

**Um app que já baixou a própria atualização não tem mais essa atualização baixada duas vezes.** Alguns apps baixam uma atualização discretamente em segundo plano e depois esperam você reiniciá-los. Clique em Atualizar no DuoUpdater e ele agora instala a cópia que já está no seu disco: a atualização é aplicada em segundos e não custa nenhum download. Antes, o DuoUpdater baixava a mesma versão tudo de novo.

**O Cua Driver e o Petex agora são compatíveis.** O DuoUpdater avisa quando qualquer um dos dois tem uma nova versão, e o Cua Driver também é atualizado com um clique e mostra suas notas de versão.

**A mesma atualização não gera mais notificações repetidas.** Quando o servidor de um desenvolvedor ficava alternando entre duas versões, cada verificação parecia uma nova atualização e publicava mais uma notificação.

**Um pacote que acabou de ser instalado não oferece mais instalar de novo.** A linha dele continuava dizendo que o pacote baixado seria reaberto.

**O DuoUpdater agora requer o macOS 15 Sequoia ou posterior.** Um Mac que ainda está no macOS 14 mantém a versão que tem e não recebe mais atualizações; todo Mac com Apple silicon pode ser atualizado para um macOS compatível.

**Nos bastidores.** As verificações de rotina não buscam mais os links de download antecipadamente, o que podia esconder por alguns instantes um botão Atualizar que funcionava sempre que o servidor de download de um desenvolvedor excedia o tempo limite.

## 0.3.95

**O Aside agora é compatível.** O DuoUpdater avisa quando sai um novo build do navegador Aside e mostra suas notas de versão.

**As atualizações que o seu macOS não consegue executar não são mais oferecidas, e a linha agora explica o motivo.** Quando um desenvolvedor informa quais versões do macOS uma versão aceita, o DuoUpdater segue essa informação: depois de uma atualização do macOS, o Little Snitch não oferece mais um build limitado a sistemas anteriores ao seu; o Xcode não oferece mais um build que exige um macOS mais novo que o seu; e um pacote de instalação cujo app exige um macOS mais novo é recusado, em vez de instalar um app que não vai abrir. As linhas que antes mostravam só um traço agora dizem “Ainda não para este macOS” ou “Requer um macOS mais recente”, com os detalhes a um clique.

**Veja com qual SDK cada app foi compilado.** Clique no selo ao lado do nome de um app e os detalhes agora dizem, por exemplo, “Criado com o SDK macOS 27.0.” — útil para saber quais apps já foram recompilados para o macOS mais recente.

**Os apps do Homebrew distribuídos em dois pacotes — um para sistemas mais antigos e outro para o mais novo — agora são lidos a partir do pacote certo.** O OnyX se divide assim para o macOS 27, e o DuoUpdater olhava apenas o pacote destinado aos sistemas mais antigos: ou não mostrava nada para o OnyX, ou o considerava atualizado em relação a uma versão que o Homebrew se recusa a instalar no 27. Agora o DuoUpdater acompanha aquele dos dois que você instalou.

**Os betas do TestFlight não perdem mais a atualização quando o TestFlight é aberto.** Um beta com um build novo esperando podia voltar para “atualizado” e ficar assim até você abrir o TestFlight de novo.

**As atualizações com um clique do Dropbox e do ToDesk baixam o arquivo certo.** No Apple silicon, o Dropbox baixava o build exclusivo para Intel, que a verificação de segurança depois recusava; ao ToDesk era oferecido o build de acesso antecipado que ele libera só para alguns usuários, em vez da versão geral.

**Reabrir conclui a atualização do Spotify na hora.** Quando o Spotify já tinha baixado a própria atualização, Reabrir ficava girando por minutos até a atualização ser aplicada.

**Os builds beta passam para as versões finais correspondentes.** Um beta do Xcode recebe a oferta do release candidate em vez de aparecer como atualizado, os betas do CotEditor passam a ver os release candidates dele, e um beta do Carbon Copy Cloner cujo ciclo de testes terminou recebe a oferta da versão em que ele se transformou, em vez de uma verificação com falha.

**As notas de versão correspondem à versão que você tem.** O Blender 5.2 mostrava as notas da 5.1, e o Raycast 1.x mostrava as notas da 2.x. O “Abrir página” do Gemini agora abre a página atual do app de desktop do Google, em vez de um erro.

**Os Ajustes explicam cada opção logo ao lado dela.** As notas longas embaixo de seções inteiras foram substituídas por uma linha curta embaixo de cada controle, e os seletores descrevem apenas a opção escolhida.

**O app agora escreve o próprio nome como DuoUpdater**, igual ao site.

## 0.3.94

**Os pacotes do Homebrew vindos de taps em que você não confiou voltam a aparecer.** Desde o Homebrew 6, o brew ignora silenciosamente os pacotes de taps não confiáveis ao listar o que está instalado, então eles sumiam do DuoUpdater sem explicação. Agora aparecem como “Não verificado · tap não confiável”, com o comando `brew trust` pronto para copiar — e, assim que você o executa (ou faz um upgrade) no Terminal, a janela se atualiza quando você volta para ela.

**Os apps que precisam de senha de administrador para se atualizar não são mais atualizados duas vezes.** Quando um app como o Tailscale já tinha baixado a própria atualização e esperava ser reaberto, o DuoUpdater não percebia e continuava oferecendo Atualizar, o que podia colidir com o instalador do próprio app. Agora a linha oferece Reabrir, e Atualizar Tudo deixa esse app de lado.

**A seção do Homebrew agora pode atualizar o próprio Homebrew.** Quando sai uma nova versão do Homebrew, uma linha no topo oferece executar `brew update` para você. Ela fica oculta se você definiu `HOMEBREW_NO_AUTO_UPDATE`.

**Um upgrade do Homebrew que falha agora mostra o erro real do brew.** A linha mostrava o conselho que o brew imprime depois do erro, ou nada, então uma mensagem como “your Command Line Tools are too outdated” nunca chegava até você. Fazer upgrade de vários pacotes de uma vez também não informa mais que terminou antes da hora.

**O ícone da barra de menus conta além de 50.** Com mais de 50 atualizações esperando, ele ficava parado em 50.

**Notas de versão: as do Claude são agrupadas em Novo, Melhorado e Corrigido, como o próprio Claude as mostra; as do Mac Mouse Fix aparecem como texto em vez de uma página incorporada; e o app do próprio Homebrew agora tem notas.**

**O `duo check` não diz mais “Everything is up to date.” quando não conseguiu realmente verificar.** Agora ele avisa quando não conseguiu ler o TestFlight ou quando a varredura de apps foi abandonada.

## 0.3.93

**As notas de versão agora aparecem no seu idioma quando um app as publica em vários.** Alguns apps distribuem as notas traduzidas junto com cada versão; o DuoUpdater pegava a tradução que o app listasse primeiro ou por último, então as notas de um app apareciam em alemão para todo mundo e as de outro mudavam de idioma de uma versão para a outra.

**Os apps que ganharam uma versão para Mac não aparecem mais como “não compatível com este Mac”.** Um app de iPhone ou iPad que você usa no Apple silicon era marcado por engano no momento em que o desenvolvedor lançava um build de verdade para Mac — justamente a mudança que torna a atualização mais disponível, e não menos.

**Um app da App Store que você também testa em beta não é mais confundido com um build do TestFlight.** Quando um desenvolvedor promovia um beta sem alterações, os dois tinham o mesmo número de build e a sua cópia comprada era entregue ao TestFlight — então a App Store nunca conseguia oferecer uma atualização para ela.

**Uma atualização da App Store que exige um macOS mais novo que o seu agora avisa isso.** Antes, a linha oferecia instalá-la mesmo assim e a App Store recusava no último passo, sem nada na tela explicando por quê.

**A janela Requisições agora mostra até quando o registro realmente vai, e marca os intervalos de datas que não consegue cobrir por inteiro.** Antes, escolher “Últimos 30 dias” em um registro que só cobria algumas horas parecia exatamente igual a escolher “Últimas 24 horas”, sem nada na tela explicando por quê.

**Você escolhe o quanto o DuoUpdater faz com os betas do TestFlight, em Ajustes → Geral.** *Quando eu recarregar* lê o que o TestFlight já sabe e pede a ele uma resposta atualizada quando você clica em Recarregar; *Mantenha tudo em dia* também deixa o DuoUpdater perguntar por conta própria, então um beta que o TestFlight instalou em segundo plano não fica mais como um ponto de interrogação até você recarregar, e um build esperando por você não passa mais despercebido atrás de um “atualizado”; *Desativado* não lê nada e diz isso nessas linhas, em vez de chutar. Os Macs que já tinham Acesso Total ao Disco começam em *Quando eu recarregar*; todos os outros, em *Desativado*.

**Abrir o TestFlight por conta própria agora basta para o DuoUpdater perceber o que ele instalou.** Um beta que você instalou pelo TestFlight ficava como um ponto de interrogação até a próxima recarga — e no macOS 27, onde o aviso “Ready to Test” do TestFlight não chega mais para apps que você já tem, isso podia levar horas.

**O Cline agora recebe atualizações, tanto dos builds finais quanto dos beta, e mostra suas notas de versão.** Até agora ele ficava com um ponto de interrogação em vez de uma versão — não tem nenhum feed de atualização do tipo que o DuoUpdater consegue ler, e não existe pacote do Homebrew para ele. O DuoUpdater agora consulta o mesmo endereço que o atualizador do próprio Cline consulta, então a atualização oferecida é a mesma que o Cline teria instalado sozinho, e o build beta continua na linha beta.

**As notas de versão que agrupam as mudanças sob títulos como Adicionado e Corrigido agora mantêm esses títulos.** Antes, todos os grupos eram mesclados em uma única lista, e não dava para saber quais mudanças eram recursos novos e quais eram correções de bugs.

**O Mac Mouse Fix agora oferece as versões beta se você ativou “Get Beta Versions” nos ajustes gerais dele.** Antes, o DuoUpdater só via as versões normais do Mac Mouse Fix, então um build beta passava despercebido até a próxima versão normal sair.

**Os apps cujo número de build é um simples contador não escondem mais as próprias versões de correção.** Para um app que informava uma versão como 12.10 com o build 282987, uma versão 12.10.1 aparecia como “já atualizado”.

**Um novo build de um app que mantém o mesmo nome de versão volta a ser anunciado.** Depois que um build era anunciado, todos os builds seguintes com esse nome chegavam em silêncio — a linha se acendia, o contador o incluía, mas nenhum aviso aparecia.

**“Atualizar Tudo” agora conta apenas os apps que foram de fato atualizados.** Um app que abre o Instalador da Apple para você terminar era contado como concluído enquanto a janela dele ainda estava aberta, então “2 apps foram atualizados” podia significar que nada tinha mudado ainda.

**Uma atualização que foi aplicada mas deixou um resto para trás agora aparece como instalada, e não como “conceder Gerenciamento de Apps”.** A nova versão já estava em execução enquanto a linha mandava você para os Ajustes do Sistema.

**Interromper “Atualizar Tudo” agora interrompe o download em andamento.** Antes, uma transferência de vários gigabytes continuava até o fim, com até cinco novas tentativas, e só então percebia que tinha sido cancelada.

**As notas de versão não se misturam mais entre dois apps que compartilham uma página de histórico de alterações, e continuam atualizadas depois de uma atualização nos apps cujas notas ficam em páginas separadas por versão.** O Antigravity e o Antigravity IDE podiam mostrar as notas um do outro por quinze minutos; o Thunderbird, o WeChat, o Opera e alguns outros continuavam mostrando as notas da versão anterior por um tempo depois de atualizar.

**A busca na lista de apps ignora acentos, como a busca dos Ajustes já fazia.** Digitar “cafe” agora encontra “Café”.

**A página Diagnóstico lista uma linha de estado para cada canal de lançamento.** Uma regra de beta ou de preview com problema ficava escondida atrás da regra estável irmã, que estava funcionando.

**Uma resposta “forbidden” do GitHub não é mais informada como limite de requisições.** Um repositório que virou privado ou um token sem um escopo levava você a adicionar um token que não teria ajudado.

**Reabrir não é mais oferecido para um app que se atualiza sozinho quando o build que está esperando é mais antigo que o que está em execução.**

**Nos bastidores.** Instalações, backups e verificações de pacotes não ocupam mais os threads em que o resto do app roda, então o menu continua respondendo enquanto uma delas está em andamento; o menu também continua fluido durante um download grande; o Registro de Versões conta todas as versões que um fornecedor lança sob um mesmo nome de versão; um backup de reversão é recusado, em vez de guardado, quando estiver faltando o executável do próprio app; a primeira abertura em um Mac novo não registra mais erros falsos de banco de dados; o `duo verify` e o `duo reconcile` agora informam um histórico de alterações cujo número de entradas despencou e um endereço de instalador que vem falhando há dias; um comando `duo` travado desiste da varredura depois de vinte segundos, em vez de ficar parado.

## 0.3.92

**Alguns apps que se atualizam sozinhos não parecem mais atualizados quando já existe uma versão mais nova.** Nos apps cujas informações de atualização ficam atrás de um servidor de download que demora a se atualizar, o DuoUpdater podia continuar vendo uma versão antiga por dias depois de um lançamento.

**As notas de versão do Kimi agora aparecem no DuoUpdater.**

**As atualizações do CodeEdit agora aparecem.** Uma versão mais nova do CodeEdit deixava a linha dele com um ponto de interrogação, em vez de oferecer a atualização.

**Nos bastidores.** A lista do Homebrew no menu é preenchida mais rápido, e os comandos `duo` iniciam mais rápido.

## 0.3.91

**Verificar de Novo em um beta do TestFlight agora dá a resposta real.** Antes, a linha virava um ponto de interrogação até a próxima recarga.

**Os betas do TestFlight mantêm suas respostas enquanto o botão de recarregar consulta o TestFlight.** Por alguns segundos, todos podiam virar pontos de interrogação.

## 0.3.90

**O super.engineering agora é compatível: verificação de atualizações, notas de versão e instalação com um clique.** Um novo nightly aparece com o que mudou nele, e Atualizar o instala para você.

**O Microsoft Edge Beta podia oferecer um build estável do Edge.** Enquanto o feed beta da Microsoft ficou vazio por um tempo, a linha indicava uma versão estável, e atualizar teria colocado essa versão por cima do seu beta.

**Os betas do TestFlight agora mostram as atualizações que o TestFlight tem para eles, inclusive os betas de apps de iPhone e iPad.** O botão de recarregar consulta o TestFlight em segundo plano, uma atualização não some mais minutos depois de você encontrá-la, e o botão TestFlight abre a página desse beta.

**Quando o DuoUpdater não consegue saber se um beta do TestFlight está atualizado, ele diz isso.** A linha mostra um ponto de interrogação em vez de considerá-lo atualizado — por exemplo, quando você saiu da sua conta no TestFlight ou não está mais testando esse beta.

**O Acesso Total ao Disco agora é explicado, e nada fica insistindo se você não o conceder.** Sem ele, o DuoUpdater não dispara mais os avisos do macOS sobre ler dados de outros apps; se um beta do TestFlight ou o CotEditor precisar dele, você é avisado uma vez sobre o motivo e onde concedê-lo.

**Reabrir desaparece assim que um app atualizado é encerrado.** Um app que deixava um auxiliar em execução continuava pedindo para ser reaberto muito depois de a atualização ter entrado em vigor.

**Um pedido de privacidade do macOS sem resposta não trava mais as verificações de atualização.** A verificação continua sem o ajuste daquele app.

**As notas de versão do Rockxy e do Ollama voltaram a ficar completas.** As do Rockxy voltam a cobrir as versões recentes, não só a mais nova, e a versão mais nova do Ollama não fica mais de fora.

**O `duo`, o complemento opcional de linha de comando, lida melhor com o TestFlight.** O `--refresh-testflight` funciona com o TestFlight aberto ou não, sem tomar a sua tela, e o `duo check` não considera mais um beta atualizado quando o TestFlight já anunciou um build mais novo.

## 0.3.89

**O Telegram Desktop volta a ter verificação de atualizações.** O Telegram mudou o nome do arquivo que publica, e a linha não conseguia mais ler uma versão a partir dele — então mostrava uma falha de verificação em vez da atualização que estava esperando.

**Um build do TestFlight de um app de iPhone ou iPad é reconhecido como tal.** O DuoUpdater o lia como uma compra da App Store, então a linha indicava o responsável errado enquanto a loja era consultada sobre uma página que não existe — em todas as verificações, durante todo o tempo em que o app continuasse instalado.

**Um beta do TestFlight é marcado com o próprio ícone do TestFlight.** As linhas cuidadas pela App Store já traziam o ícone da loja; as cuidadas pelo TestFlight escreviam o nome por extenso, então o mesmo tipo de linha era marcado de duas formas diferentes.

**O cabeçalho da janela Rede fica parado quando você troca de aba.** As duas abas posicionavam os títulos em alturas ligeiramente diferentes, então alternar entre elas fazia a janela parecer tremer.

## 0.3.88

**Rolar por toda a sua lista de apps voltou a ser fluido.** Uma rolagem rápida pela lista completa perdia quadros; agora cada linha informa sua altura sem precisar ser construída antes.

**As notas de versão de um app da App Store agora sempre vêm da App Store.** Quando a consulta da própria loja para um app falhava ou não encontrava nada, a janela podia recorrer às notas da outra distribuição desse app — um build diferente, com números de versão próprios — descrevendo uma versão que nunca seria oferecida à sua cópia.

**O Windscribe no canal Beta ou Guinea Pig recebe os builds desse canal.** O DuoUpdater lê qual canal de atualização você escolheu nos ajustes do próprio Windscribe, então uma cópia que segue uma linha de pré-lançamento não é mais considerada atualizada enquanto existem builds mais novos nessa linha. A janela também mostra as notas desses builds de pré-lançamento, que antes só apareciam para os estáveis.

**O Windscribe agora tem verificação de atualizações, com suas notas de versão.** Uma cópia com um build mais antigo aparece com a versão para a qual pode ir e o que mudou nela; antes, o DuoUpdater não tinha como ver a versão do Windscribe. A atualização continua sendo feita pelo instalador do próprio Windscribe, que configura partes do app que ficam fora do app em si.

**Uma atualização não é mais aplicada a um app que sumiu enquanto você clicava.** Se o app for desinstalado, substituído ou deixar de poder ser lido entre o clique e o início da instalação, o DuoUpdater agora para e avisa, em vez de instalar por cima daquele local mesmo assim.

**O `duo`, o complemento opcional de linha de comando, não considera mais concluída a instalação de um pacote antes da hora.** Instalar um app distribuído como `.pkg` abre o instalador do macOS e deixa o resto com você, mas o resumo o contava como instalado — “1 installed” enquanto nada tinha sido substituído ainda. Agora esses casos são contados à parte. A saída `--json` também identifica em cada linha o que aconteceu com aquele app, então um script não precisa mais ler a explicação em inglês para distinguir uma falha de um pulo proposital.

**Nos bastidores.** A reverificação feita antes da instalação, que protege a atualização com um clique, agora protege também o `duo install`, e as verificações pelas quais um download precisa passar antes de substituir um app ficam em um único lugar para os dois caminhos que as usam.

## 0.3.87

**Clicar em Atualizar não deixa mais de fazer efeito quando uma fonte de atualização se contradiz.** Se a verificação feita no momento do clique volta com uma versão mais antiga que a oferecida pela linha, o DuoUpdater agora avisa e mantém a atualização disponível. Antes, informava que o app já estava atualizado e o tirava da lista, e a mesma atualização reaparecia na verificação seguinte.

**As atualizações do Fork voltam a ser oferecidas quando ele está no canal Develop.** O DuoUpdater lia o ajuste de canal do Fork ao contrário e seguia o feed Stable, que fica bem atrás — então uma cópia Develop aparecia como atualizada enquanto o próprio Fork oferecia uma versão mais nova.

**O Mac Performance Monitor agora mostra suas notas de versão.** O app as publica no repositório, e não no feed que lemos, então a janela não tinha nada para mostrar.

**O CotEditor agora é compatível, tanto na linha final quanto na beta.** A linha que uma cópia segue é definida pela versão em execução e pelo ajuste “Update to prereleases when available” do próprio CotEditor, então uma cópia beta recebe o próximo beta em vez de uma versão que a faria voltar atrás.

**Um app instalado pela App Store nunca recebe a oferta de um download de outro lugar.** Quando a consulta da própria loja falha ou volta vazia, a linha agora diz que a loja cuida dele, sem número de versão. Antes, a verificação podia cair na outra distribuição do app — um build diferente, com números de versão próprios — e oferecer instalá-lo por cima da sua cópia da loja.

**Um app nunca recebe a oferta de uma atualização que o levaria para uma versão mais antiga.** Alguns feeds listam uma versão estável acima de um pré-lançamento que na verdade está mais adiante, e aceitá-la teria feito o app voltar atrás.

**Um erro longo em uma linha não empurra mais o resto da lista para baixo.** Ele fica limitado a duas linhas, com o texto completo ao passar o cursor.

## 0.3.86

**Mais quatro apps são compatíveis: WhatCable, Qoder IDE, Qoder e Yaak.** Cada um ganha verificação de atualizações e instalação com um clique, e as notas de versão deles são lidas na janela como texto, e não como uma página incorporada.

**Os dois apps da Qoder para Mac agora são diferenciados.** O IDE e o app de desktop compartilham o nome e a página de download, mas seguem linhas de versão separadas, então cada um agora é acompanhado individualmente.

**Os builds beta do WhatCable e do Yaak são acompanhados na própria linha.** Uma cópia com um beta não tinha fonte nenhuma e ficava em “Falhou”; agora recebe o próximo beta, com notas de versão separadas das estáveis. No WhatCable, isso inclui também a versão estável em que um beta acaba se tornando — aceitá-la leva a cópia para a linha estável.

## 0.3.85

**Verificar seus apps da App Store usa uma fração da rede que usava antes.** Cada verificação baixava de novo a página de produto de cada app da App Store; agora as páginas ficam guardadas por uma hora e a loja é consultada sobre todos os seus apps em poucas requisições, em vez de uma por app. Com o intervalo de verificação de cinco minutos, isso dá cerca de um terço a menos de tráfego no total; com o intervalo padrão de seis horas, as páginas continuam expirando entre as verificações, então a economia é menor.

**Verificar um app de novo não baixa mais todos os apps da App Store outra vez.** Um único “Verificar de Novo” descartava todas as páginas de produto em cache, então a próxima verificação agendada pagava por todas elas; agora ele atualiza apenas o app que você pediu.

**Verificar os apps distribuídos pelo GitHub custa uma fração da rede que custava antes.** Cada verificação baixava de novo a descrição completa de cada versão, mesmo quando nada tinha sido publicado; agora pergunta ao GitHub se a versão mudou desde a última vez e não baixa nada quando não mudou. Uma vez por dia, relê cada versão por completo, então uma versão retirada é percebida em até um dia.

**Os apps acompanhados em uma linha beta ou nightly do GitHub agora pedem uma versão, em vez de uma página inteira delas.** A versão mais nova é a resposta quase sempre, e a página completa só é buscada nas rodadas em que não é.

**A verificação de atualização do Vorssaint não depende mais de um redirecionamento.** O repositório dele foi renomeado, e seguir o nome antigo fazia a requisição cair silenciosamente no limite anônimo de requisições do GitHub; agora a verificação vai direto ao nome novo.

**Nos bastidores.** O artefato de lançamento agora é compilado, assinado e notarizado em um Mac hospedado pelo GitHub, com uma procedência de build que qualquer pessoa pode verificar, e o registro de requisições diferencia uma resposta em cache de uma vinda da rede.

## 0.3.84

**Os registros de requisições que você exporta não levam mais o nome da sua conta.** Cada linha de um app instalado na sua pasta pessoal mostrava o caminho completo; agora mostra `~`, qualquer que seja a forma como você exporta o registro.

**A aba Requisições agora diz o que cobre e o que não cobre.** Ela registra as buscas que o próprio DuoUpdater faz. Uma página de notas de versão carrega as próprias imagens e fontes, e as atualizações da App Store e do Homebrew são feitas por ferramentas separadas — nada disso aparece ali, e agora a janela diz isso em vez de deixar você supor.

**Copiar URL agora codifica o endereço que entrega.** Os caminhos com espaço — os downloads do Firefox, do Thunderbird e do Bartender entre eles — eram copiados sem tratamento, o que um navegador perdoa e uma linha de comando não.

**A linha do beta do CapCut não informa mais uma verificação com falha.** Entre um beta e outro — depois que um vira versão final e antes que o próximo comece — o fabricante não publica nada nessa linha, o que aparecia como uma linha vermelha e um botão Tentar de novo que nunca poderia funcionar. Agora a linha simplesmente fica sem resposta dessa fonte até o próximo beta aparecer.

**O Audacity agora mostra o selo que diz com o que ele foi feito.** Ele inicia por um pequeno lançador que passa o controle ao programa real ao lado dele, e o selo era lido do lançador, que não vincula nada.

**As notas de versão da App Store agora chegam no seu idioma.** Elas sempre eram buscadas no idioma padrão da loja, então um Mac em chinês ou japonês continuava lendo as notas em inglês.

**As atualizações do próprio DuoUpdater agora aparecem com o nome dele na janela Rede.** A verificação de versões, as notas de versão e o download dele eram todos registrados com a coluna de app em branco.

**Nos bastidores.** Uma credencial incluída no caminho de um endereço web agora é removida antes de a requisição ser registrada, como sempre foi feito com uma que estivesse na string de consulta.

## 0.3.83

**A janela Tráfego de Downloads agora se chama Rede e tem uma segunda aba.** Downloads é o registro que você já tinha — quanto cada atualização custou como arquivo. Requisições é nova: cada busca que o DuoUpdater faz em seu nome, para que serviu, a qual app pertencia e quanto custou, com um campo de filtro para fazer perguntas ao registro em vez de rolar por ele. Os números no topo respondem ao que você filtrou, e não ao total acumulado.

**Verificar atualizações do Spotify agora quase não usa a rede.** O Spotify não publica um arquivo de versão em lugar nenhum, então a verificação lê a versão de um instalador inicial de dois megabytes — e baixava o arquivo inteiro todas as vezes, dia e noite. Agora ela pergunta se esse arquivo mudou e pula o download quando não mudou.

**O PDF Expert agora encontra suas atualizações e mostra o que mudou.** Ele lia uma lista de versões que o fabricante parou de atualizar em 2022, então se dizia atualizado qualquer que fosse a sua versão. Agora segue a lista que o próprio atualizador do app usa, e passa a trazer também as notas de versão das versões anteriores, não só da mais nova.

**Os builds de preview do UTM agora recebem as próprias atualizações, instalam com um clique e mostram as notas de versão correspondentes.** Uma cópia preview era comparada com a linha final e considerada atualizada sem nenhum aviso; agora segue a própria linha e, quando aceita a versão final dessa linha, volta para a linha final.

**Nos bastidores.** As requisições registradas passaram para o mesmo armazenamento que o registro de downloads, então os dois relatos de um mesmo download não podem mais divergir. Seu registro atual é mantido intacto.

## 0.3.82

**Mais quinze apps passam a ser acompanhados, e todos menos um instalam com um único clique.** AgentsView, AnythingLLM, Chatbox, ChatGPT Classic, DSH Desktop, FluidVoice, GitHub Copilot, Kun, Meetily, Microsoft 365 Copilot, OpenLogi, OpenSuperWhisper, Paseo, T3 Code — nas linhas alpha e nightly — e Vorssaint. O ChatGPT Classic é a exceção: ele é verificado para você, mas vem com um instalador que atualiza o próprio app, então quem o executa continua sendo você.

**Oito apps agora mostram as notas de versão dentro do DuoUpdater, em vez de mandar você para uma página web.** Xcode, Antigravity, Antigravity IDE, AnyDesk, AnythingLLM, Chatbox, Headlamp e Helium. Três deles nem tinham para onde mandar você: a página do AnyDesk responde com um desafio contra bots, os criadores do Helium não publicam página de notas alguma, e o Antigravity IDE não tinha link de nenhum tipo.

**Os betas do Xcode dizem o que mudou em cada beta.** A linha oferecia um número de build e um link; agora lista as notas da Apple para o beta que você usa e para todos os betas anteriores dessa versão.

## 0.3.81

**Word, Excel, PowerPoint, Outlook e OneNote agora percebem quando a atualização foi aplicada.** Esses cinco continuavam oferecendo reabrir o instalador que você já tinha concluído, e nunca passavam a oferecer Reabrir — esperar ou verificar de novo não resolvia.

**Uma linha esperando para reabrir volta a se explicar, nas duas janelas.** Quando um app estava ao mesmo tempo à frente do que o fornecedor publica e esperando para reabrir, a linha acima do botão descrevia outra coisa totalmente diferente; a janela e o menu também discordavam sobre as linhas que esperavam Atualizar Tudo reabri-las.

**As etiquetas das linhas não espremem mais o nome do app em russo.** Algumas etiquetas também reaproveitavam textos de strings sem relação em todos os idiomas traduzidos.

**As notas de versão agora aparecem nos apps cujo fornecedor informa a data de uma versão sem o horário.** Essas versões não deixavam rastro em lugar nenhum.

**Uma página de notas de versão que nos recusamos a abrir agora diz por quê.** Antes, ela ficava em branco, o que parecia exatamente um app que não publica notas.

**As notas de versão do WeChat DevTools nightly não estão mais vazias.**

**Nos bastidores.** O tratamento de versões e de datas de lançamento foi unificado para que um número de build nunca seja lido como versão comercial, e a linha do tempo de lançamentos não inventa mais um horário que o fornecedor nunca informou.

## 0.3.80

**As verificações com falha agora aparecem na janela.** A janela não mostrava nada numa linha cuja verificação tinha falhado — nem numa que você ignorou, numa que você pulou ou numa gerenciada pela App Store, pelo Toolbox ou pelo TestFlight —, o que parecia exatamente “atualizado”. As duas janelas agora dizem a mesma coisa sobre o mesmo app, e o botão Tentar de novo está nas duas.

**“Verificar de Novo” em qualquer linha consulta só aquele app.** Ele também relê quais apps estão em execução, então é a forma rápida de corrigir uma bolinha verde que parece errada.

**Pular e ignorar agora funcionam pelo menu de clique secundário da janela.** As duas linhas mandavam você clicar com o botão direito para desfazer, numa janela cujo menu não tinha essa opção.

**A verificação em segundo plano não tira mais as notas de versão que você está lendo.** A verificação de hora em hora descartava todas as notas já carregadas, então um painel de Notas de Versão aberto voltava a mostrar o indicador de carregamento. Agora só uma recarga que você pediu as recomeça.

**Os downloads interrompidos são verificados antes de serem considerados completos.** Um servidor que reenviava o arquivo inteiro, ou parava antes do fim, era aceito sem conferência, e o problema só aparecia um passo depois, como uma instalação que falhava por causa de um arquivo compactado corrompido. Os downloads por trás de um proxy que antes falhavam sempre agora funcionam.

**Atualizar um app não faz mais uma nova varredura de todos os apps do seu disco.** Cada clique fazia duas varreduras completas de todos os seus aplicativos para examinar o que você tinha pedido.

**As notas de versão do Chrome não podem mais travar.** Uma simples mudança de visual no blog do Google bastava para travá-las por minutos; agora elas carregam prontamente, seja qual for a aparência da página.

**Um instalador baixado não é mais descartado e baixado de novo.** Quando um fornecedor escrevia a mesma versão de duas formas (`v1.2.3` e `1.2.3`), o pacote em espera não era reconhecido e Reabrir podia continuar esperando uma troca que já tinha acontecido.

**Uma instalação como administrador que falhou não é mais confundida com você clicando em Cancelar.** Nenhum erro era mostrado, e aquele app deixava de oferecer atualizações com um clique, sem aviso, até você pedir acesso de administrador de novo no menu da linha dele.

**A bolinha verde de “em execução” agora percebe todos os apps.** O macOS nunca anuncia a abertura ou o encerramento de alguns apps, e a bolinha deles ficava errada até algo sem relação atualizá-la.

**“Atualizar Tudo” não fica mais aparecendo e sumindo durante uma recarga**, e um app que você atualiza no meio de uma recarga não volta a oferecer a atualização que já instalou.

**Uma verificação que falha no momento em que você clica em Atualizar agora avisa**, em vez de ser tratada como “nada a fazer”.

**Nos bastidores.** As datas de lançamento escritas em formatos incomuns são lidas corretamente, a verificação de endereço nas páginas de notas de versão cobre todas as grafias equivalentes, e a manutenção de rotina não acessa mais o disco toda vez que algum app do seu Mac abre ou é encerrado.

## 0.3.79

**O selo do Docker agora descreve a interface do Docker, e não o daemon dele.** A linha dizia “nativo”; o Docker Desktop é um app Electron. O selo é lido do pacote do app, e o pacote do Docker é um invólucro: o programa que ele indica é um serviço em segundo plano escrito em Go, não traz framework próprio, e o app que realmente desenha as janelas fica um nível dentro dele. Tudo estava sendo lido corretamente, só que do arquivo errado. O DuoUpdater agora olha o app aninhado quando — e somente quando — o externo não traz nada por conta própria e contém exatamente um app desse tipo que comprova com o que foi feito, para que um processo auxiliar distribuído junto de uma interface real continue sem poder emprestar sua identidade ao app que o contém. O Docker aparece como Electron 42.5.0 e, dos cento e quarenta e seis apps da lista no computador em que isto foi escrito, é a única linha que muda.

**As notas de versão do CleanShot X voltaram a ser legíveis — inclusive as da 5.0.** O CleanShot lançou sua maior versão em anos e reconstruiu a página de histórico de alterações junto com ela: a data passou para cima do número da versão, surgiram duas novas camadas em volta dela, e uma versão com recursos novos agora coloca uma introdução e dois links de vídeo entre a versão e a lista de mudanças. O leitor que o DuoUpdater usava deixou de reconhecer tudo isso. O que tornava isso pior que um painel vazio é que ele não parecia vazio: as notas que já tinham sido salvas para a versão anterior continuavam na tela sob o título da versão nova, então o painel dizia “5.0” em cima das mudanças da 4.8.10, e nada em lugar nenhum dizia o contrário.

**As notas salvas antes de uma versão ser publicada agora são relidas, em vez de serem aceitas para sempre.** Essa é a outra metade da mesma história. O DuoUpdater soube da existência da 5.0 seis minutos antes de o CleanShot publicar o que havia nela, salvou a página como estava e a arquivou sob a 5.0 — e, a partir daí, cada verificação encontrava algo já salvo e nunca mais olhava. Agora as notas salvas são confirmadas com o fornecedor uma vez por sessão antes de serem tratadas como definitivas, então uma versão cujas notas chegam atrasadas se completa na visita seguinte, em vez de continuar errada.

**Tudo o que você abre pela barra de menus agora abre no primeiro clique.** Escolher Histórico de alterações em uma linha — ou os Ajustes, ou o Registro de Versões — não fazia absolutamente nada na primeira vez, e funcionava do segundo clique em diante. Reabrir o menu fazia cada tentativa voltar a ser a primeira, então, para quem abre o menu, clica uma vez e espera uma janela, nunca funcionava. O primeiro clique dentro do menu era gasto trazendo o DuoUpdater para a frente, em vez de fazer o que se pretendia. A janela aberta agora também fica na frente: ela era trazida para cima e empurrada de volta para baixo no mesmo instante, que é a outra forma pela qual isso parecia um clique que não fazia nada.

## 0.3.78

**Um app que deixa o próprio nome em branco agora ganha um mesmo assim.** O Eudic (欧路词典) aparecia na lista com um ícone, uma versão e absolutamente nada no lugar do nome. O pacote dele declara, sim, um nome de exibição — e o deixa vazio, porque os nomes reais ficam nas traduções do app —, e o DuoUpdater tomava essa resposta vazia como definitiva, em vez de fazer a próxima pergunta. Agora ele recorre ao outro nome do app e, depois, ao nome do arquivo do app, então nenhuma linha fica sem nome. Aqui, um app em cento e cinquenta foi afetado; o ponto é que a informação já estava lá e estava sendo ignorada.

**Reabrir agora avisa quando o app se recusou a encerrar, em vez de parecer um clique que não fez nada.** Se um app tem uma janela esperando por você — um pedido para salvar, uma tela de login, algum diálogo —, o macOS não deixa que ele encerre, e não há nada que o DuoUpdater possa fazer: a janela é do app. O DuoUpdater ficava girando por trinta segundos e depois mostrava o mesmo botão de novo sem explicação, o que parece exatamente um botão quebrado, então as pessoas clicavam de novo. Agora a linha diz o que aconteceu e indica o app para você resolver essa janela. Nada foi alterado e a nova versão já está instalada, então só falta mesmo reabrir — e, se você simplesmente encerrar o app por conta própria nos próximos dez minutos, o DuoUpdater percebe e o reabre na versão nova sem que você precise clicar em nada.

**As notas de versão do 欧路词典 voltaram a ser de uma versão, e não de dezesseis anos delas.** O app publica todo o seu histórico — todas as versões desde a 2.5.0 — dentro das notas da versão mais nova, então o painel de detalhes mostrava tudo isso sob o título “26.9.0” e era preciso rolar por uma década para achar o que tinha acabado de mudar. Agora cada versão tem a própria entrada na lista, como acontece com todos os outros apps.

**O selo que diz com o que um app foi feito agora exige prova para o Tauri, e não só semelhança.** O Tauri não deixa nada para encontrar num pacote — nenhum framework, nenhuma pasta própria —, então esse selo era deduzido da forma como o app foi empacotado mais o fato de ele vincular a visualização web da Apple. O Longbridge atende a tudo isso e não é Tauri: ele desenha as próprias janelas com o mesmo renderizador que o Zed usa e incorpora uma visualização web em um canto da interface. O DuoUpdater agora lê a impressão digital do próprio Tauri no binário antes de afirmar isso, então um app só é chamado de Tauri quando é um — e o Longbridge aparece como o app nativo para Mac que ele é.

**O CapCut não fica mais vermelho porque os servidores da ByteDance tiveram um meio segundo ruim.** O endpoint que o DuoUpdater consulta para saber a versão do CapCut responde com um código de sucesso e então, cerca de uma vez em cinquenta, com um objeto de erro no lugar da resposta — um tempo limite interno na própria infraestrutura da ByteDance, uns 390 bytes onde se esperavam 436 kilobytes. Nada do lado de cá conseguia distinguir isso de o CapCut ter mudado o formato da resposta, então a linha dizia que a verificação tinha falhado, o que soa como “isto está quebrado e alguém precisa consertar” para algo que se resolve sozinho na tentativa seguinte. Esse formato específico agora é reconhecido pelo que é: a requisição é repetida na hora, e só é informada como um problema real se continuar acontecendo por cinco dias.

## 0.3.77

**Todos os apps da lista agora dizem com o que foram feitos.** A linha de um app da App Store sempre trouxe o selo da loja, e todas as outras linhas eram iguais — um app Sparkle, um app Electron e um nativo não se distinguiam. Agora cada nome traz o símbolo da própria tecnologia — clique nele para ver uma palavra e uma frase, ou passe o cursor para ver a dica: Electron, Tauri, Flutter, Qt, Java, Chromium, Mac Catalyst, um app de iPhone no Apple silicon ou um app nativo para Mac —, com a versão do runtime quando ela pode ser lida como um fato (Electron 42.4.1, Qt 6.2, o Chromium que um app incorpora, o Tauri com que foi compilado). Isso é lido do próprio pacote — o framework que um empacotador teve de incluir, o runtime de que um lançador precisa, as bibliotecas que o binário vincula —, então é um fato sobre o que está instalado, e não um palpite a partir do nome do app. Quando um nome comprido não deixa espaço, o símbolo sai de cena em vez de empurrar o nome para uma segunda linha: o nome é a linha. Desative tudo isso em Ajustes → Geral.

**O LibreOffice não alega mais um rebaixamento para a versão que você já tem.** O índice de downloads dele lista versões com três partes (`26.8.0`), enquanto a cópia instalada informa quatro (`26.8.0.3`), e completar a parte que faltava com um zero fazia a cópia instalada parecer mais nova — então a linha mostrava um aviso discreto de que “o fornecedor está atrás de você” sobre um app que estava exatamente em dia. Uma fonte que publica menos partes do que o app informa agora é lida como descrevendo a mesma versão, e não uma mais antiga; uma reversão de verdade continua sendo indicada.

**Um ajuste adicionado por uma atualização agora é destacado uma vez.** Uma preferência nova que surge no meio da janela de Ajustes é uma preferência que ninguém encontra. A engrenagem da barra de menus ganha um ponto azul depois de uma atualização que adicionou um ajuste, a página onde ele fica ganha um na barra lateral, e o próprio controle mantém o seu até você olhar para ele. Só para quem de fato atualizou para essa versão — uma instalação nova não é recebida com pontos em recursos que simplesmente fazem parte do app que acabou de conhecer.

## 0.3.76

**Os apps com manifesto Electron adicionados na versão anterior agora podem de fato ser atualizados.** A 0.3.75 ensinou o DuoUpdater a ler o arquivo que esses apps trazem dentro de si, e ele o lia — descobria a nova versão, o download certo para o seu Mac e o checksum para conferi-lo — e depois não tinha para onde mandar nada disso. O botão de instalar nunca aparecia, e o `duo install` explicava a recusa com um motivo que não era o verdadeiro. O caminho de instalação foi conectado nesta versão. Na prática, talvez você não veja diferença nenhuma: esse leitor fica atrás de todas as regras escritas à mão, então só atua em um app que nada mais cobre — o que hoje, no computador em que isto foi compilado, não é o caso de nenhum. Ele importa para o app que você instalar amanhã e para o qual ninguém escreveu uma regra.

**Um download que tiraria você de um build nativo agora é recusado.** O Apple silicon ainda consegue executar apps Intel por tradução, o que fazia um download só para Intel passar na verificação “isto vai rodar no seu Mac?” e ser instalado sem problemas — deixando você com uma cópia traduzida de um app que rodava de forma nativa, sem aviso, e com cada atualização futura fazendo a mesma coisa de novo. Agora toda instalação no lugar compara o que você tem com o que chegou e recusa essa troca. O caminho inverso, ou de um build universal para um só para Apple silicon, é normal e continua permitido.

**Quando não consegue provar qual é a arquitetura de um download, ele agora recusa em vez de chutar.** Alguns fornecedores publicam um build para Apple silicon ao lado do build padrão, e a única forma de saber que o padrão é o build Intel é perceber que o outro existe. Se essa segunda verificação não voltar sem problemas — o servidor do fornecedor a recusa, a conexão cai ou os dois discordam sobre qual versão são —, o DuoUpdater não trata mais esse silêncio como uma resposta. Ele informa a versão e não oferece instalação, que é o resultado honesto.

**Uma regra quebrada não pode mais sumir do Diagnóstico.** Nos apps cobertos tanto por uma regra escrita à mão quanto pelo novo leitor de manifesto — a maioria deles, de propósito —, uma falha da regra era anulada pelo sucesso do leitor logo em seguida, então um app cuja regra tinha de fato quebrado continuava aparecendo como saudável. Agora os dois são registrados separadamente. O leitor de manifesto também informa as próprias falhas pela primeira vez; três apps na máquina de desenvolvimento estavam apontando para endereços que vinham retornando “não encontrado” havia algum tempo, algo que antes nada teria dito em voz alta.

**As linhas que conseguem ver uma atualização mas não conseguem instalá-la agora oferecem a mesma coisa nos dois lugares.** A barra de menus mostrava um botão chamado “Abrir” que abria o Finder, e a janela não mostrava nada para a mesma linha.

## 0.3.75

**Os apps feitos com Electron agora são reconhecidos sem que ninguém precise cadastrá-los antes.** Muitos apps para Mac trazem dentro de si um pequeno arquivo que diz onde ficam suas atualizações. Até agora o DuoUpdater só conhecia aqueles para os quais alguém tinha escrito uma regra à mão — todos os outros ficavam na sua lista sem versão ao lado e sem nenhum jeito de avisar que tinha saído um build novo. Agora ele lê esse arquivo diretamente, do mesmo jeito que sempre leu o do Sparkle, então um app assim fica coberto no dia em que você o instala, e não no dia em que alguém tiver tempo de cuidar dele.

**Os apps que já tinham uma regra escrita à mão continuam intactos.** O novo leitor fica atrás delas, então só pode preencher uma lacuna — nunca assumir algo que já estava funcionando.

**Dois detalhes decidem se o download oferecido é o certo, e ambos foram resolvidos conferindo apps reais, sem suposições.** Alguns fornecedores marcam um build Intel como o download “principal” mesmo publicando um para Apple silicon ao lado; outros dão ao build para Apple silicon um nome de arquivo que não se diferencia em nada do Intel, então o nome não revela nada. O DuoUpdater escolhe pela arquitetura e, quando não tem certeza de que um download vai rodar no seu Mac, informa a versão e deixa de oferecer a instalação — em vez de entregar algo que instala sem problemas e depois não abre.

## 0.3.74

**Se você usa o build beta, release candidate ou nightly de um app, o DuoUpdater estava acompanhando a linha errada sem avisar.** Ele descobre em qual linha você está encontrando o seu build na própria lista de versões do fornecedor — mas, quando um pré-lançamento mantém o mesmo número de versão público da versão estável da qual saiu, que é o normal para um pré-lançamento, ele acabava associando a entrada estável. O efeito era silencioso: nada de errado aparecia na tela, você simplesmente nunca ficava sabendo do próximo build da sua própria linha, e as notas de versão mostradas eram as da linha estável. Descobrimos isso instalando os builds de pré-lançamento reais do Supacode e do TypeWhisper e observando o que acontecia; os dois agora seguem a linha em que realmente estão.

**O beta do CapCut mostrava uma versão que você não tem.** A linha dizia “9.3.4545 → 9.4.0-beta6”, enquanto o próprio CapCut, o Finder e todos os outros atualizadores chamavam a sua cópia de 9.4.0-beta5. Alguns apps guardam a versão real em um campo diferente do da maioria, e o DuoUpdater lia o de aparência mais arrumada do seu lado da seta, enquanto lia o real do lado do fornecedor. A atualização oferecida sempre foi a certa — só o rótulo estava errado. Agora as duas metades da linha vêm do mesmo lugar, para o CapCut e para os outros sete apps feitos desse jeito.

**MacWhisper, GitHub Copilot for Xcode, TypeWhisper e OpenUsage agora mostram suas notas de versão.** Os quatro tinham o painel de notas vazio: os feeds de atualização deles não trazem nota nenhuma, o que só foi percebido quando cada um foi comparado com o que o fornecedor de fato publica. O DuoUpdater agora lê a página de notas de versão do próprio MacWhisper, o arquivo de histórico de alterações do Copilot e o site de histórico de alterações do TypeWhisper, e aponta o OpenUsage para a lista de versões dele.

**O Helium agora se atualiza pelo próprio serviço de atualização, o que traz o canal beta dele e downloads bem menores.** Ele era acompanhado pela lista pública de versões, que só mostra builds estáveis — então quem estava no beta do Helium recebia o estável. O serviço próprio dele também publica patches, então uma atualização de rotina fica em torno de 40 MB, em vez de um novo download de 124 MB. Verificado com um build estável e com um beta, e o download é conferido com a chave de assinatura da sua cópia instalada antes de qualquer coisa ser substituída.

## 0.3.73

**As versões beta, developer e nightly do Firefox e do Thunderbird agora são acompanhadas corretamente — até hoje, nenhuma dessas cinco linhas tinha informado uma única atualização.** Elas eram lidas do arquivo público de versões da Mozilla, que só publica a versão exibida para você, e instalar um beta tira o “b5” dela: um beta do Firefox se chama 155.0 durante todo o ciclo, então a única pergunta feita era “155.0b5 é mais nova que 155.0?”, e a resposta é não. O nightly era pior — a Mozilla lança um por dia e todos se chamam 157.0a1, então um ciclo de quatro semanas não produzia absolutamente nada. O DuoUpdater agora consulta o próprio serviço de atualização da Mozilla, o mesmo endereço que o atualizador integrado do Firefox usa e que o app traz escrito dentro de si, e compara o identificador de build que os dois lados têm. Conferido com os downloads reais das cinco linhas antes do lançamento: o identificador que esse serviço informa é idêntico, byte a byte, ao que está dentro do app que você tem; um beta um build atrás agora mostra sua atualização, e um nightly compilado mais cedo no mesmo dia também. As versões estável e ESR nunca foram afetadas e continuam intactas. Um limite que vale deixar claro: esse serviço não publica data de lançamento, então, para essas cinco linhas, o Registro de Versões ainda anota quando o DuoUpdater viu um build pela primeira vez, e não quando a Mozilla o lançou.

## 0.3.72

**Wispr Flow, AionUi e Devin agora se atualizam com um clique, em vez de só avisar que existe uma versão nova.** Os três já enxergavam suas atualizações, mas nenhum conseguia aplicá-las, com a justificativa de que o fornecedor publica builds separados para Intel e Apple silicon e o DuoUpdater não tinha como escolher. Quando se mediu em vez de presumir, esse motivo não se sustentava: os endpoints de onde esses três são lidos já são os de Apple silicon, e o DuoUpdater só roda em Apple silicon — nunca houve escolha a fazer. Cada download foi baixado e conferido antes de ser integrado: o app certo lá dentro, assinado pelo mesmo desenvolvedor da cópia que você tem, notarizado pela Apple e, no caso do AionUi, conferido com o checksum que o próprio manifesto publica. Depois, cada um foi instalado de verdade por cima de uma cópia mais antiga e voltou na versão nova.

**O Grok Bot agora é acompanhado — versões novas e atualizações com um clique.** O app de desktop da xAI é compilado e assinado pela Anysphere, a empresa por trás do Cursor, e se atualiza pelo próprio serviço de lançamentos do Cursor — e é por isso que nenhum dos caminhos habituais respondia por ele: nada de feed do Sparkle, nada de página na App Store, nenhum repositório público de lançamentos e um cask do Homebrew que devolve a atualização ao próprio app. Em vez disso, o DuoUpdater lê o endpoint de versão do próprio fornecedor. Havia outros dois endpoints disponíveis, e os dois foram deixados de lado por motivos concretos: o que fica por trás do botão de download em x.ai não publica número de versão nenhum, e o que o atualizador do próprio app usa responde com um corpo vazio quando você já está em dia — um silêncio que não daria para distinguir de um endpoint quebrado. A instalação foi conferida antes de ser integrada: a imagem de disco traz o app de verdade, assinado pelo mesmo desenvolvedor da cópia que você tem e notarizado pela Apple. Uma coisa ele deliberadamente não oferece: notas de versão. A xAI não publica nenhuma para este app, e o único histórico de alterações que ela publica pertence a outro produto.

**Comet e Msty Studio também se atualizam com um clique, e uma nova verificação fica de olho em apps que poderiam fazer isso e não fazem.** Eram os dois últimos do grupo que enxergavam atualizações mas não conseguiam aplicá-las, e nenhum dos dois precisou de nada novo — só de um olhar mais atento ao que o fornecedor realmente envia. O link de download do Comet é assinado e expira em uma hora, então o botão de atualizar aponta para o gateway da própria Perplexity, e o link é gerado no momento em que você clica, e não horas antes, quando a verificação rodou. A Msty publica quatro downloads num único arquivo, com o de Intel listado primeiro, e a impressão digital usada para verificar o download vinha justamente dessa primeira entrada; agora ela está amarrada ao build de Apple silicon que de fato é baixado, o que em geral também detecta uma versão publicada entre a verificação e o clique, em vez de instalá-la em silêncio. Os dois foram baixados e passaram pelas barreiras reais de instalação antes do lançamento. A lição mais ampla não tinha nada a ver com nenhum dos dois: nada no DuoUpdater conseguia perceber um app deixado apenas com detecção por um motivo que já não era verdade, então a varredura noturna de receitas agora avisa quando um app que ela só observa já está nos entregando um instalador.

**O QQ音乐 agora é acompanhado — versões novas, atualizações com um clique e suas notas de versão na janela.** Nenhum dos caminhos habituais respondia por ele. Ele não publica feed do Sparkle e nem traz o framework do Sparkle; seu cask do Homebrew devolve a atualização ao próprio app; e o endpoint de atualização citado no próprio binário responde com 200 e um corpo vazio a tudo o que conseguimos perguntar — um silêncio que não dá para distinguir de um endpoint quebrado, por isso ele foi deixado de lado. O que o DuoUpdater lê em vez disso é o arquivo de dados a partir do qual a própria página de download do fornecedor é montada: essa página chega como uma casca vazia e se preenche a partir desse arquivo, que é também o único lugar onde as notas de versão existem — não há blog, nem appcast, nem página por versão. Por isso as notas são lidas direto dali e exibidas na própria janela do DuoUpdater, e a atualização instala a imagem de disco notarizada indicada nessa mesma resposta. Uma armadilha que vale registrar: esse arquivo ainda carrega um segundo registro para Mac, de seis anos atrás, ao lado do atual, então as duas regras se baseiam no nome de arquivo com versão do download para Mac, e não na palavra “Mac”. E um limite que vale deixar claro: o arquivo publica a versão que você vê, mas nunca o número de build por trás dela, então uma nova compilação de uma versão que mantém o mesmo nome fica invisível aqui. Ele não tem como inventar uma atualização que não existe — só não consegue enxergar esse tipo específico.

**O TimeMachineEditor agora é acompanhado — versões novas e atualizações com um clique.** Nenhum dos caminhos habituais respondia por ele: nada de feed do Sparkle (o app não traz nem um endereço de feed nem o framework que o usaria), nada de página na App Store, nenhum repositório público de lançamentos e um cask do Homebrew que devolve a atualização ao próprio app. O que ele tem é um pequeno site do fornecedor cujo único link de download informa a versão no próprio texto — a mesma página, lida da mesma forma, em que a verificação de versão do próprio Homebrew se apoia; ou seja, é a interface que o fornecedor pretende oferecer, e não um palpite. A atualização é instalada pelo pacote instalador do próprio fornecedor, e não como uma simples troca do app, e isso é proposital: o download também instala um agendador em segundo plano, uma ferramenta de linha de comando e um launch daemon fora do app, então trocar só o app deixaria uma cópia nova ao lado de um agendador desatualizado, sem nada que percebesse a diferença.

**O Little Snitch agora é acompanhado, tanto nas versões estáveis quanto nas nightly.** A Object Development publica um arquivo de versão ao qual o próprio atualizador do app recorre — o mesmo que o Homebrew lê — e o DuoUpdater o lê diretamente, porque o Little Snitch não publica feed do Sparkle e seu cask devolve a atualização ao app. As duas versões compartilham a mesma identidade, o que normalmente torna impossível distingui-las; esta se entrega na string de versão, onde um build nightly escreve a palavra por extenso (“6.5 nightly (7301)”), enquanto o build estável aparece como um simples “6.4.1”. Vale dizer o que isso deliberadamente não faz: não instala a atualização para você. O Little Snitch roda uma extensão do sistema e um serviço privilegiado em segundo plano junto com o app, e ainda não foi verificado numa máquina real se trocar só o app mantém essas partes intactas — então o DuoUpdater avisa que a versão nova saiu e leva você ao download do próprio fornecedor, em vez de arriscar com um filtro de rede.

**O Carbon Copy Cloner agora é acompanhado, e não vai tentar levar você de uma versão principal para outra.** A Bombich mantém três gerações ativas ao mesmo tempo — CCC 5, 6 e 7 —, todas se apresentando ao sistema com a mesma identidade, o que torna “existe algo mais novo?” uma pergunta mais difícil do que parece: 7.1.6 de fato vem depois de 6.1.13 na ordenação, mas passar de uma para a outra é uma compra à parte, e o CCC 7 exige um macOS mais novo do que uma máquina com CCC 5 talvez esteja rodando. Responder só pelo número de versão teria dito a todo dono de CCC 5 e 6 que havia uma atualização gratuita esperando, para sempre — e estaria errado todas as vezes. Por isso o DuoUpdater lê cada geração no seu próprio endereço e só oferece a próxima versão dentro da geração que você realmente tem. As versões beta também são detectadas, para quem as ativou dentro do CCC. Por enquanto é só detecção — o CCC instala um auxiliar privilegiado ao lado do app, o que é uma promessa maior do que as atualizações com um clique que já existem aqui — e vale registrar por que nada conseguia enxergar essas atualizações antes: o próprio feed de atualização do app responde a toda requisição com sucesso, com uma página totalmente vazia.

**Uma atualização que o seu Mac não consegue rodar não é mais baixada nem instalada.** Todo pacote de app informa o macOS mais antigo em que vai abrir, e alguns fornecedores também informam o mais novo — “este build não é para um sistema tão recente”, que é como um app que ainda não se adaptou ao macOS 27 avisa isso. O DuoUpdater não lia nenhum dos dois. Nos apps acompanhados por um feed do Sparkle o limite mínimo já era respeitado, mas eles são minoria: entre os apps de um Mac típico, os que são lidos no endpoint do próprio fornecedor ou em versões do GitHub são a maior parte, e uma versão do GitHub não publica requisito de macOS em lugar nenhum. Assim, um app que já tinha passado a exigir um macOS mais novo que o seu podia ser oferecido, baixado por inteiro, trocado — e depois não abrir. Agora o DuoUpdater lê o requisito no próprio app baixado, logo ao lado da verificação que já existia de que ele foi compilado para o seu processador, e recusa a troca em vez de substituir uma cópia que funciona por uma que não vai abrir. O limite máximo informado pelo fornecedor também é respeitado, quando um feed o publica, então um build que o desenvolvedor marcou como não compatível com o seu macOS nem chega a ser oferecido. Três limites que vale deixar claros. Ler o requisito no download significa que o download já aconteceu — isso evita uma instalação quebrada, não o tráfego, porque para a maioria dos apps não há onde perguntar antes. Um app cuja versão mais nova o seu Mac não consegue rodar vai continuar mostrando essa atualização e continuar se recusando a instalá-la; a recusa agora informa qual versão do macOS ela exige, mas o DuoUpdater ainda não guarda essa resposta para parar de oferecê-la. E a verificação cobre os caminhos em que o próprio DuoUpdater troca o pacote do app — um pacote instalador entrega o arquivo ao macOS, que aplica os requisitos do próprio pacote, e o Homebrew e a App Store escolhem seus próprios builds; os apps que vieram da seção de iPhone e iPad da App Store são pulados de propósito, já que a versão que informam é uma versão do iOS, e compará-la com o macOS seria pior do que não verificar nada. Uma coisa que ele ainda não diz em voz alta: quando um desenvolvedor marca um build como não compatível com o seu macOS, essa atualização simplesmente não é oferecida, e o app aparece como em dia em vez de explicar o motivo. Num Mac mais antigo isso se resolve sozinho no dia em que você atualizar o macOS. Num Mac novo demais, não se resolve — e ali se deve uma resposta melhor do que o silêncio.

## 0.3.71

**O 百度网盘 agora é acompanhado — versões novas, atualizações com um clique e suas notas de versão na janela.** Nenhum dos caminhos habituais estava aberto. Ele não publica feed do Sparkle; o cask do Homebrew não responde por uma cópia instalada manualmente; e o manifesto de atualização citado no próprio pacote do app está morto — esse arquivo, o gêmeo arm64 dele e o diretório que contém tudo isso respondem 404. Por isso o DuoUpdater lê o endpoint a partir do qual a própria página de download do fornecedor é montada e instala a imagem de disco arm64 notarizada indicada nessa mesma resposta. As notas de versão chegam do mesmo jeito: a página “版本更新” tem uma aba Mac版, mas a página em si chega vazia e se preenche a partir de uma API, então o DuoUpdater lê essa API diretamente e exibe os últimos quarenta lançamentos na própria janela. Um limite que vale deixar claro: esse feed publica a versão que você vê, mas nunca o número de build por trás dela, então uma nova compilação de uma versão que mantém o mesmo nome fica invisível aqui. Ele não tem como inventar uma atualização que não existe — só não consegue enxergar esse tipo específico.

**Uma verificação que falhou agora diz que falhou, em vez de mostrar um espaço em branco.** Um app cuja versão só o endpoint do próprio fornecedor sabe informar tinha um único jeito de dizer “sem resposta”: um traço vazio, que é também a aparência de um app que nada cobre. Assim, o endpoint de um fornecedor que expirava ou mudava de lugar parecia exatamente “o DuoUpdater não acompanha este app” — um veredito com cara de definitivo, sem botão Tentar de novo e sem entrar na contagem de “apps que não puderam ser verificados”. Agora esses casos são uma verificação que falhou, que é o que eles são: um botão Tentar de novo, um lugar na contagem e o motivo informado. Mas não tudo, de propósito: uma condição a respeito da qual o seu Mac simplesmente não pode fazer nada — nenhuma receita para a linha de lançamentos em que você está, um endpoint que exige uma identidade que esta máquina não tem — continua sendo o traço discreto de sempre, e uma verificação que falhou três rodadas seguidas continua saindo do aviso em vez de ficar presa nele para sempre. Um app instalado pelo JetBrains Toolbox também mantém seu botão “abrir o Toolbox” quando a leitura de versão por trás dele falha, já que abrir o Toolbox era a resposta de qualquer jeito.

**O lembrete “reabra para aplicar” agora some depois que você reabre o app.** Quando o próprio atualizador de um app baixava um build em segundo plano, o DuoUpdater avisava e oferecia um botão Reabrir na notificação. Usá-lo funcionava — o app voltava no build novo e dizia “Agora em 1.0.” —, mas o lembrete que ele substituía continuava na Central de Notificações, por baixo, ainda pedindo para você reabrir algo que você tinha acabado de reabrir. O DuoUpdater esperava o lembrete *deixar* de ser relevante, e o momento em que ele verificava era justamente o único momento que já tinha sido levado em conta. Agora ele remove o lembrete sempre que não há nenhuma reabertura pendente, o que também limpa um lembrete deixado para trás por um app que aplicou a própria atualização enquanto o DuoUpdater não estava rodando.

## 0.3.70

**Apps que lançam vários builds com o mesmo número de versão agora são tratados direito — em todo lugar.** Um app de Mac carrega duas strings de versão: a que ele mostra para você (“1.0”) e um número de build que de fato vai aumentando. A maioria dos apps muda as duas. Alguns mudam só o build: o Amp lançou dez builds num único dia, todos chamados 1.0; o Surge já lançou quatro versões diferentes como 6.9.0; os builds de prévia da JetBrains fazem o mesmo. O DuoUpdater decidia “isso mudou?” comparando a versão *mostrada* em cerca de uma dúzia de lugares, e para esses apps essa comparação só podia responder “não” — ou, onde a pergunta era “são iguais?”, “sim” —, não importava o que tivesse acontecido de fato. O que vem a seguir é o que isso quebrou. É um erro só, descoberto porque o Amp o deixou visível.

**Reabrir não parece mais travar por três minutos para depois relatar uma falha que não aconteceu.** Clicar em Reabrir num app cujo próprio atualizador tinha um build esperando deixava o indicador girando por três minutos e depois dizia que tinha falhado — quando, na verdade, a atualização tinha sido aplicada em um ou dois segundos e o app já tinha reaberto no build novo. O DuoUpdater ficava observando a versão mostrada à espera de uma mudança que nunca ia acontecer. Medido no Amp: 189 segundos de indicador girando para uma troca que levou menos de um. Agora isso se resolve em bem menos de um segundo, e uma falha real continua sendo relatada como falha.

**Reabrir não oferece mais um build que já está desatualizado.** Quando o atualizador de um app tinha baixado um build e o desenvolvedor já tinha publicado outro depois, o DuoUpdater ainda oferecia Reabrir — então você reabria e ficava imediatamente um build atrás, exatamente o que essa verificação foi escrita para evitar. Essas linhas agora oferecem **Atualizar**, que baixa o build atual.

**Pular uma versão não silencia mais um app para sempre.** Esta é a que vale a pena conhecer. “Pular esta versão” serve para recusar um lançamento e deixar o próximo passar. Ela registrava só a versão mostrada, então, num app que mantém o mesmo nome de versão entre builds, pular uma vez recusava *todos* os lançamentos futuros — de forma permanente, sobrevivendo a reinicializações, sem nada na tela indicando que o app tinha ficado em silêncio. Agora pular registra o build que foi recusado. Uma consequência da correção: uma versão pulada por um DuoUpdater anterior será oferecida mais uma vez, porque o registro antigo não tem como dizer a qual build se referia. Pulá-la de novo a registra corretamente.

**A reversão volta a aparecer em atualizações que pareciam não ter mudado nada.** A bancada esconde uma reversão que não faria nada — e, para esses apps, toda reversão parecia não fazer nada, então a linha sumia depois de uma atualização real, enquanto um backup completo ficava no disco sem nenhum jeito de chegar até ele.

**O lembrete para reabrir volta a ser anunciado uma vez por build, e sobrevive ao desenvolvedor lançar outro.** A 0.3.69 substituiu um lembrete que se repetia a cada cinco minutos por um que fala uma vez por build preparado — mas identificava o build pelo nome, então, para esses apps, anunciava o primeiro e depois ficava em silêncio para todos os seguintes. Isso foi corrigido. Além disso: se um app se recusa a fechar porque tem trabalho não salvo, o DuoUpdater guarda um lembrete para reabri-lo depois que você responder. Esse lembrete era descartado se o desenvolvedor publicasse outro build enquanto você decidia, deixando o app fechado depois da troca sem nada para reabri-lo. Agora ele acompanha o build novo.

**Uma atualização da App Store que falhou não é mais registrada silenciosamente como sucesso**, e um pacote instalador baixado não é mais tratado como o que está sendo oferecido no momento quando é um build mais antigo. Os dois problemas vinham da mesma comparação. O histórico de lançamentos também contava dez builds de um app como um só lançamento; a partir de agora conta separadamente, embora o histórico já registrado não possa ser recuperado.

**A própria linha diz qual build a reabertura vai aplicar.** Ela mostrava “1.0 → 1.0” — uma linha que não apontava diferença nenhuma. Agora mostra “1.0 (129) → 1.0 (130)”, e só quando o build é o que mudou; quando os nomes de versão já são diferentes, a linha continua igual. A mesma correção chega às dicas do Reabrir, à notificação, à nota que explica por que uma instalação foi adiada e à recusa do `duo install`.

## 0.3.69

**O 微信输入法 e o 豆包输入法 voltam a ser atualizados com um clique — e do mesmo jeito que eles se atualizam sozinhos.** A atualização com um clique para métodos de entrada foi retirada na 0.3.25, no mesmo dia do lançamento, depois que os ajustes de método de entrada de alguém sumiram. O problema estava no formato da instalação: ela substituía o app inteiro, como faz um instalador na primeira instalação. Um método de entrada é registrado no macOS pela *localização* do seu app, e esses dois apps se atualizam sem mexer nessa localização — eles mantêm o app e trocam o que está dentro dele. Agora o DuoUpdater faz a mesma coisa, então o app registrado atravessa a atualização como o mesmo app, e uma falha em qualquer ponto deixa a cópia que você estava usando exatamente onde estava. E nenhum dos dois pede mais a sua senha.

**Antes que qualquer um deles seja atualizado, tudo o que aprenderam é copiado primeiro.** Seu dicionário, seus ajustes e o estado da sua conta não ficam dentro do app, então a cópia de reversão que o DuoUpdater já guardava não tinha como responder por eles. Agora é tirado um snapshot deles antes de toda atualização de método de entrada, e eles são restaurados junto com a reversão, e a cópia sai quase de graça — 578 MB de um deles levam um décimo de segundo e quase nada de disco. Isto é uma rede de segurança, não um conserto: o que um app decide fazer com os seus dados na próxima vez que abre é código do próprio app rodando, e nada pode se colocar na frente disso. Agora existe algo para onde voltar.

**Uma atualização não tira mais, silenciosamente, a capacidade de um app de se atualizar sozinho.** Quando o DuoUpdater precisava de um administrador para substituir um app, ele restaurava o dono do app, mas não as permissões com que o app tinha sido instalado — e um download normalmente é descompactado com permissões mais restritas do que as que um instalador define. Nos dois métodos de entrada, essa é a diferença entre o próprio atualizador conseguir concluir a próxima atualização e não conseguir limpar a própria bagunça. As permissões com que um app foi instalado agora são levadas para a cópia que o substitui.

**O DuoUpdater para de pedir que você reabra o mesmo app a cada cinco minutos.** Um app que se atualiza sozinho deixa a versão nova guardada no disco e espera você fechá-lo. O DuoUpdater percebia isso a cada verificação e postava um lembrete toda vez, então um build que você tinha decidido não reabrir ainda continuava insistindo pelo tempo que você o deixasse ali. Agora cada build é anunciado uma vez: reabra, pule ou ignore o app e ele fica quieto, e o build seguinte se anuncia normalmente.

**Um app esperando para ser reaberto conta como atualização, e um ignorado não conta mais.** Uma versão nova que já está no disco *é* uma atualização — só foi baixada antes — então agora ela entra no contador do ícone e na linha “N atualizações disponíveis”, em vez de numa contagem separada ao lado. Os apps ignorados foram no sentido oposto: um app que você tinha ignorado podia acender o contador enquanto a linha dele mostrava uma etiqueta discreta “Ignorado” e nenhum botão para clicar, então o número apontava para algo com que você não podia fazer nada. Ignorar e pular agora significam a mesma coisa nas três superfícies — o lembrete, o contador e a lista.

**O 搜狗输入法 agora é acompanhado — perguntando ao próprio atualizador dele, em vez de ler o site.** A página de histórico de alterações da Sogou publica números de versão com três segmentos, enquanto a cópia instalada tem quatro, então comparar com ela exigiria cortar antes a versão real. A própria verificação de atualização do app, por outro lado, responde na numeração do próprio pacote. O DuoUpdater consulta esse endpoint do mesmo jeito que o app e lê o lançamento a partir dele, com os quatro segmentos, então uma nova compilação que muda só o último fica visível. Este é só de detecção: o atualizador da Sogou faz muito mais do que trocar o app — ele registra de novo um gerador da Visualização Rápida, move seus dados para um novo local e força o encerramento do método de entrada —, então a atualização em si fica por conta dele. Uma coisa que vale saber, e que é obra da Sogou, não nossa: o endpoint responde de acordo com a versão do macOS que faz a pergunta, e um Mac com macOS 28 perguntando por si mesmo recebe um build de 2023. O DuoUpdater não pergunta por si mesmo, então a versão que você vê é a atual em qualquer Mac.

**Notas de versão que uma correção posterior teria acertado são lidas de novo, em vez de ficarem erradas para sempre.** As notas ficam em cache por versão, partindo do raciocínio de que as notas de uma versão lançada nunca mudam. Isso vale para as notas, mas não para o que o DuoUpdater consegue extrair delas, então um app cujas notas saíram embaralhadas ficava assim naquela versão, não importava quantas correções de análise saíssem depois. Agora cada entrada do cache registra qual geração da lógica de extração a gravou, e uma gravada por uma geração mais antiga é buscada de novo. Os dois caches fazem isso — históricos de alterações de apps e notas de fórmulas do Homebrew.

**Uma verificação que falha na CDN de alguém é tentada mais uma vez antes de ser considerada quebrada.** 502, 503 e 504 significam, todos, que um intermediário não conseguiu alcançar o servidor por trás dele: a requisição nunca chegou, então a mesma requisição um instante depois costuma funcionar. A verificação do Headlamp morreu exatamente assim — o GitHub respondeu 504 sem nenhum cabeçalho de limite de requisições. Esses três agora ganham uma nova tentativa, depois de oito décimos de segundo. Só esses três, de propósito: um 500 é o próprio servidor falhando, e repetir o pedido quase sempre só reproduz a falha; e tentar de novo após atingir o limite de requisições gasta justamente a cota de que ele está reclamando.

**As notas de versão de uma fórmula do Homebrew acompanham a versão a que pertencem.** As notas eram guardadas por fórmula, nunca por versão, então, depois que as notas de uma fórmula eram carregadas, toda consulta seguinte recebia as notas daquela primeira versão pelo resto da sessão — inclusive depois que aparecia uma versão mais nova. Lê-las também ocupava a fila da qual o resto da lista de fórmulas dependia, então um `brew info` lento podia travar a lista em volta.

**Clique com o botão direito num app na barra lateral da bancada para abri-lo.** É a mesma opção Abrir que as linhas da barra de menus sempre ofereceram, agora na janela em que é mais provável que você queira usá-la.

**Descartar um instalador baixado leva junto o erro que ele deixou para trás.** Jogar fora um pacote preparado já fazia a linha voltar para Atualizar, mas uma falha em vermelho da tentativa que você tinha acabado de cancelar continuava ali — e nada jamais a apagaria, já que um erro só é retirado quando a linha fica em dia, o que nunca acontece com uma linha que ainda oferece uma atualização. Agora ele vai embora junto com o download.

**O `duo`, o complemento opcional de linha de comando, para de se descrever de forma imprecisa.** O `--timeout` foi removido — ele era aceito, documentado e não era lido por nada. O `--budget` é documentado pela primeira vez, e a única mensagem que o menciona agora informa um número real de minutos, em vez de sempre “15”. O `--max-calls` alegava um padrão de 20 quando o padrão é 6. Uma opção numérica que recebe algo que não é número agora é um erro: `duo verify --max-concurrency 1x` era ignorado e a varredura rodava com o padrão de quatro, o que é o contrário do que quer alguém que está deliberadamente deixando uma varredura mais lenta. E o `duo verify` conta as requisições que realmente fez: um feed que responde 502 e dá certo na nova tentativa não informa mais um `ok` limpo depois de ter perguntado duas vezes sem avisar. O `-h` funciona em todo lugar onde o `--help` funciona.

## 0.3.68

**Mais quatro apps acompanhados, mais dois canais de lançamento, e todos se atualizam no lugar.** CapCut, Canva e WorkBuddy nos dois sites em que é distribuído — o internacional e o chinês têm ciclos de lançamento independentes, então uma instalação só recebe a versão e as notas do seu próprio site. Termius e VSCodium ganham os canais Beta e Insiders ao lado dos builds estáveis que já eram cobertos. O segundo canal do CapCut é o mais complicado: ele é escolhido por um botão dentro do próprio CapCut e não aparece em lugar nenhum do número de versão, então o canal em que você está é lido da cópia no disco, e não deduzido do build que por acaso está rodando. Vale saber se você marcar essa opção: o DuoUpdater vai oferecer o beta mais novo assim que ele existir, o que pode ser antes do momento em que a liberação gradual do próprio CapCut chegaria até você.

**Os canais de prévia do Android Studio não oferecem mais um build mais antigo que o seu.** O Google lista os lançamentos na ordem em que foram publicados, não por versão, e o DuoUpdater procurava nessa lista três vezes separadas — uma para a versão, uma para a data, uma para o download —, então um release candidate publicado depois de um canary mais novo podia fornecer a versão de uma entrada e o arquivo de outra. Em 26 de agosto, o canal Canary respondeu com 2026.1.4 RC 2 quando o 2026.2.1 Canary 2 já tinha saído. Agora essas respostas precisam vir todas da mesma entrada.

**Uma versão recompilada não instala mais a cópia que ela deveria substituir.** Quando um projeto recompila uma versão sem mudar o número, os dois arquivos ficam sob a mesma tag — o KeePassXC publica `KeePassXC-2.7.11-1-arm64.dmg` ao lado do original `KeePassXC-2.7.11-arm64.dmg` — e o DuoUpdater pegava o que estivesse listado primeiro. Essa ordem é alfabética, o que desta vez por acaso colocou a recompilação em primeiro, e da próxima a teria colocado em último. Nada disso era visível: a versão na linha estava certa, só o arquivo por trás dela estava errado. Agora o arquivo certo é escolhido pelo que o próprio nome do arquivo diz.

**Builds nightly e snapshot são reconhecidos como os builds de pré-lançamento que são.** O nightly do VLC, o snapshot do KeePassXC e o nightly do Freelens são instalados com o mesmo nome e o mesmo identificador de pacote do app estável, então a string de versão é a única coisa que os denuncia — e ela não estava sendo lida. Eles contavam como instalações estáveis, e é assim que um nightly acaba recebendo uma versão comum para se sobrescrever. O nightly do DB Browser for SQLite é lido pelo próprio nome de arquivo do app pelo mesmo motivo, e ali o problema era real, só que escondido: a versão congelada dele fica acima da estável atual só até a estável alcançá-la, e a partir desse momento toda instalação nightly receberia, sem aviso, um build estável.

**Reabrir um app informa o que realmente aconteceu.** Alguns apps trazem um segundo app dentro do próprio pacote — o Surge guarda o Dashboard ali — e, quando só esse app interno precisava ser reiniciado, o DuoUpdater dizia que o app externo tinha sido reaberto, quando nada tinha acontecido. Agora ele informa o resultado do próprio app interno e não mostra mais uma notificação de reabertura para uma reabertura que nunca aconteceu.

**Uma atualização que já foi baixada avisa isso, e pode ser desfeita.** Uma linha com um pacote instalador já baixado mostrava um botão azul Instalar e mais nada — nada dizia que o download já estava concluído, nem que o botão reabre o instalador em vez de recomeçar a atualização, e não havia como mudar de ideia. Agora isso aparece na própria linha, em vez de ficar escondido numa dica, e **Descartar Instalador Baixado** no menu de clique com o botão direito da linha joga o download fora e faz a linha voltar para Atualizar. Descartar um pacote enquanto uma instalação do mesmo app já estava em andamento também podia jogar fora um pacote que tinha acabado de ser baixado; isso não acontece mais.

**Botões de notas de versão que apontavam para páginas desativadas voltam a abrir páginas ativas.** A Microsoft renomeou as páginas de notas de versão do Edge para empresas e o Termius mudou seu histórico de alterações de lugar, então três canais do Edge e o Termius estavam levando você a uma página que não existia mais. Nada nunca tinha verificado se essas páginas continuavam no ar, e é por isso que elas podiam se deteriorar indefinidamente enquanto todo o resto parecia saudável — agora elas são verificadas periodicamente. O canal Dev do Edge fica sem botão nenhum: a Microsoft parou de publicar notas para ele, e todas as páginas que ainda existem pertencem a outra linha de lançamentos.

**O Raycast é acompanhado até a versão 2, e só nos Macs que conseguem rodá-la.** O Raycast 2 exige o macOS Tahoe e Apple silicon. Um Mac que não atende a isso continua na linha da versão 1 e não é mais avisado de um lançamento que nunca poderia ter instalado. As duas linhas também passam a ter as próprias notas de versão, então uma instalação da versão 1 mostra o histórico da versão 1, e não o da versão 2.

**As notas de versão são exibidas na própria janela do DuoUpdater para mais apps.** BetterDisplay nos três canais, Shotbase e WorkBuddy nos dois sites. As notas do BetterDisplay não terminam mais com o código bruto do botão de download e não repetem mais a lista de colaboradores em cada lançamento.

**O `duo`, o complemento opcional de linha de comando, recusa uma linha de comando que não entende.** Uma opção digitada errado era ignorada, e uma opção ignorada é lida como se você nunca a tivesse passado — então `duo verify --githubb` verificava, sem avisar, todas as receitas em vez da que você pediu. Opções desconhecidas, uma opção sem o seu valor e argumentos soltos agora são erros que dizem o que o comando realmente aceita, e o `--help` funciona depois de qualquer comando.

## 0.3.67

**Os builds de pré-lançamento e internos do BetterDisplay agora são oferecidos a quem pediu por eles.** O BetterDisplay traz suas três linhas de lançamento num único feed de atualização e escolhe entre elas com dois botões nos próprios ajustes. O DuoUpdater só conseguia deduzir a sua linha pelo build que você por acaso estava rodando, o que não diz nada sobre um botão que você ativou mas ainda não usou — então alguém com os dois botões ativados, num build estável, ouvia que estava em dia enquanto o próprio atualizador do BetterDisplay oferecia uma versão quatro lançamentos à frente. Agora a sua escolha real é lida no BetterDisplay, incluindo o caso em que ativar os builds internos também mantém os pré-lançamentos comuns chegando. Os builds de prévia exclusivos para Apple silicon ficam de fora de propósito, para que um Mac Intel nunca receba um que não consegue rodar.

**Trocar o canal de lançamento de um app duas vezes seguidas não deixa mais a linha presa na resposta antiga.** Mudar o botão de canal faz o DuoUpdater verificar aquele app de novo, e uma segunda mudança enquanto a primeira verificação ainda rodava era descartada — a linha continuava oferecendo um beta a alguém que tinha acabado de desativar os betas, até que algo sem relação por acaso disparasse outra verificação. Agora a mudança mais recente assume o lugar da anterior, e uma verificação interrompida no meio deixa os apps que não chegou a alcançar marcados para a próxima rodada, em vez de registrá-los como resolvidos. As linhas também entram mais cedo no estado de verificação depois de uma mudança, então sobra menos tempo em que a resposta na tela é uma que o seu botão já invalidou.

## 0.3.66

**Um app que fica dentro de outro app agora é fechado e reaberto junto com ele.** Alguns apps trazem um segundo app completo dentro do próprio pacote — o Surge guarda o Dashboard ali. O macOS trata esse app como um app separado, então nada o fechava quando uma atualização era aplicada ao app em volta dele: ele continuava rodando a versão que tinha acabado de ser substituída, a partir de uma cópia que já não estava onde ele achava que estava, e dali não conseguia mais se comunicar com o app a que pertence. Agora esses apps são fechados junto com o app em que ficam e reabertos depois dele, e a janela em que você realmente estava trabalhando é a que volta para a frente. Só apps que você mesmo poderia ter aberto são tratados assim; os processos auxiliares invisíveis que um app roda para si mesmo são deixados em paz.

**Pontos de reversão que tinham deixado de ser criados sem aviso voltam a ser criados.** Um app pode bloquear um dos próprios arquivos para que nada consiga apagá-lo, e a cópia guardada para reversão herdava esse bloqueio — então ela nunca podia ser substituída pela seguinte, e uma única tentativa interrompida podia deixar para trás uma cópia que nada conseguia remover. A partir daí, toda atualização daquele app seguia sem caminho de volta, e dizia isso numa linha que não dava motivo nenhum. Um app no próprio Mac do desenvolvedor tinha ficado nesse estado por dois dias. As cópias guardadas para reversão não carregam mais o bloqueio, o app instalado fica exatamente como o desenvolvedor o configurou, e uma cópia que ficou presa não consegue mais impedir a que deveria substituí-la.

**Uma atualização que funcionou não informa mais que falhou.** O macOS pode colocar uma versão nova no lugar e depois falhar ao remover a que foi deslocada. Isso era levado ao pé da letra: o DuoUpdater dizia que um app não tinha sido atualizado quando tinha, ou que não havia ponto de reversão enquanto um completo estava guardado nos backups — e, no primeiro caso, mandava você conceder uma permissão que você já tinha concedido e que não teria ajudado de qualquer forma. Agora o que realmente aconteceu no disco é verificado antes de qualquer coisa ser informada.

**As linhas de versão não repetem mais dígitos que o número de versão já contém.** Quando um app está esperando para ser reaberto, a linha mostra a versão que você está rodando e aquela em que a reabertura vai deixar você. Os dois lados traziam um número de build, que é o que torna a diferença legível quando um desenvolvedor lança vários builds com o mesmo nome de versão — e puro ruído quando as versões já são diferentes. A linha do Chrome gastava a largura inteira imprimindo “151.0.7922.174 (7922.17…” e acabava antes dos dígitos que realmente mudaram. Agora os números de build só aparecem quando são eles que mudaram.

## 0.3.65

**Agora uma só palavra para reabrir um app e concluir a atualização.** Um app cujo próprio atualizador já tinha colocado a versão nova no lugar pedia que você o “reiniciasse”; um que guarda a versão nova à parte até você fechá-lo pedia que você o “reabrisse”. Essa diferença era real nos bastidores e não fazia diferença nenhuma para você: o mesmo clique nos dois casos, e o mesmo resultado se você nunca clicasse, já que a atualização entra na próxima vez que você fechar o app de qualquer jeito. Agora aparece Reabrir em todo lugar — inclusive nas notificações, nas dicas e no ajuste que faz isso por você —, que é também a palavra que o Chrome, o Claude e a maioria dos apps que se atualizam sozinhos colocam na sua frente. Só o inglês chegou a ter duas palavras para isso; alemão, japonês, russo e chinês sempre usaram uma só, e espanhol e francês passam a usar a palavra que já empregavam em outros lugares.

## 0.3.64

**Uma atualização que precisa de um administrador agora pede um, em vez de falhar e pôr a culpa numa permissão.** Se uma troca precisava de senha era decidido olhando a pasta em que o app fica, e não o próprio app. Tudo o que o macOS instalou como root — todo app da App Store e qualquer app instalado por um pacote instalador — passava nesse teste, seguia pelo caminho que não pede senha e não tinha como terminar: remover a versão antiga exige permissão de escrita nos diretórios dentro dela. O macOS informa essa recusa com o mesmo código que usa para uma permissão de Gerenciamento de Apps negada, então a falha chegava como um pedido para conceder o Gerenciamento de Apps, o que nunca ajudaria, porque o obstáculo era o dono dos arquivos. Num Mac comum, isso afetava todos os apps da App Store e mais alguns outros, e atingia contas de administrador — contas padrão já eram encaminhadas corretamente. Essas atualizações agora seguem pelo caminho que funciona, e o app mantém o dono que tinha, em vez de passar silenciosamente a ser seu.

**Os apps da App Store agora ganham um ponto de reversão como todos os outros.** Os backups os pulavam, partindo do raciocínio de que a loja sempre pode baixar de novo um build anterior. Ela não pode — a App Store só oferece a versão atual de um app —, o que fazia da loja o único caminho que aplicava uma atualização sem ter como desfazê-la. Agora esses apps ganham backup antes de uma atualização como qualquer outro, e, como a cópia é feita por clonagem, ela quase não ocupa espaço em disco até a atualização de fato substituir o original. Restaurar um deles avisa o que é específico da loja: a atualização reaparece na lista de Atualizações na hora, e é reaplicada sozinha se as atualizações automáticas de apps estiverem ativadas. E quando uma atualização da loja nunca ia ser aplicada — um app de iPhone rodando num Mac, um título não vendido na sua região —, nenhum ponto de reversão é mais criado, então uma linha não pode mais oferecer reverter para a versão que já está rodando.

**O Longbridge Desktop agora é acompanhado, nas suas duas linhas de lançamento.** Stable e Preview ganham, cada uma, detecção de versão, instalação com um clique do build oficial para Apple silicon e notas de versão exibidas na própria janela do DuoUpdater, com ilustrações.

**As notas de versão do WhatsApp agora aparecem enquanto a verificação na App Store ainda está em andamento.** A página da App Store mostrada nessa janela tinha sido registrada sob um nome que a busca nunca conseguiria encontrar, então o painel de notas ficava vazio em vez de mostrá-la.

**O cabeçalho do menu mostra mais coisas em menos espaço.** A versão do próprio DuoUpdater agora fica ao lado do nome, e clicar nela abre as notas de versão. “Atualizar Tudo” foi para uma linha própria, onde um rótulo traduzido tem espaço para ser lido por inteiro, e as ações na parte de baixo viraram ícones. O aviso que anunciava a autoatualização do DuoUpdater foi removido — em vez disso, o brilho ao lado da versão se acende e continua aceso até você ler o que mudou. Uma linha de status comprida demais para o menu agora termina em reticências, em vez de esticá-lo.

**Os Ajustes não cortam mais as opções de atualização que oferecem.** Os dois menus que decidem como uma atualização é aplicada cortavam os próprios rótulos em vários idiomas. O texto ficou mais curto, e eles passam para uma segunda linha quando as palavras ainda precisam disso.

**A janela Novidades diz quando cada versão foi lançada.** Toda versão na barra lateral agora traz a data de publicação.

## 0.3.63

**Atualizações específicas de arquitetura agora escolhem o build que este Mac realmente consegue rodar.** Alguns apps publicam a mesma versão duas vezes num único feed do Sparkle — uma para Apple silicon e outra para Intel — e o DuoUpdater desempatava pelo endereço de download que por acaso vinha primeiro na ordenação. Agora ele lê o requisito de hardware do feed e, quando o fornecedor o deixa em branco, a arquitetura no nome do arquivo. O build nativo sempre vence, e um build que este Mac não consegue abrir não é oferecido. As versões do GitHub recebem o mesmo tratamento, sem declarar quebrada uma receita perfeitamente saudável só porque o artefato mais novo dela é para outra arquitetura.

**As verificações de atualização do ChatGPT agora seguem a linha de liberação associada à conta.** A OpenAI às vezes mantém contas empresariais num build de desktop anterior enquanto um novo chega primeiro às contas pessoais. O DuoUpdater omitia o plano da conta nessa verificação, o que silenciosamente selecionava a linha mais cautelosa para todo mundo: ele podia dizer que a cópia instalada estava de alguma forma à frente enquanto o próprio ChatGPT já baixava um build mais novo, ou oferecer um build que o próprio atualizador do app substituiria de novo. Agora ele envia o rótulo do plano, lido do estado de login do ChatGPT/Codex, na mesma requisição de atualização que o app faz. Se esse rótulo não estiver disponível, ele mantém o comportamento cauteloso; as credenciais em si nunca entram na requisição nem nos diagnósticos.

**Uma reabertura que o macOS nunca responde não consegue mais travar todas as atualizações seguintes.** O Launch Services de vez em quando aceita um pedido para reabrir um app atualizado e nunca dá retorno. A linha ficava em “Reabrindo…” para sempre, o botão Reiniciar continuava desativado e a atualização do próprio DuoUpdater ficava esperando atrás dela. Uma abertura que não respondeu depois de um minuto agora é liberada como falha, então a linha se recupera e o resto do atualizador continua funcionando.

**O Registro de Versões continua preenchido quando a barra de rolagem é arrastada depressa.** A pilha preguiçosa antiga podia ficar para trás num salto longo, deixando por um instante a janela em branco enquanto as linhas eram criadas em volta da nova posição. Agora o registro usa uma lista com reciclagem que consegue saltar direto para o destino. O controle de atualizar também mantém o mesmo tamanho ao alternar entre a seta e o indicador de progresso, então a linha de baixo não dá mais um tranco quando uma verificação começa.

**O Tráfego de Downloads agora marca as atualizações que usaram um patch binário.** Os downloads novos registram o caminho que de fato foi concluído — e não só se um patch foi oferecido — e ganham um selo Delta no histórico. Os downloads de patch da 0.3.62, claramente menores, também são reconhecidos, mesmo tendo sido registrados antes de o registro de tráfego ter um campo de caminho.

## 0.3.62

**As atualizações agora baixam só o que mudou, quando o desenvolvedor as publica desse jeito.** Alguns apps lançam um pequeno patch junto com cada versão — o suficiente para transformar a versão que você tem na nova, sem baixar tudo de novo. O DuoUpdater ignorava esses patches e baixava o pacote completo toda vez. Agora ele usa o patch quando há um que corresponde exatamente ao build que você tem. A última atualização do ChatGPT ficou em 1,9 MB em vez de 605 MB; a do Docker, em 87 MB em vez de 582 MB. O resultado é o mesmo aplicativo de qualquer forma — mesma assinatura, mesmos bytes, conferido com o download completo antes deste lançamento. Quando nenhum patch serve para o que você tem, ou um deles falha ao ser aplicado, o download completo acontece como antes, então nada pode deixar de ser instalado por causa disso.

**O DuoUpdater não baixa mais uma atualização que o próprio app já está baixando.** Muitos apps também se atualizam sozinhos, e nós dois indo buscar o mesmo arquivo de 600 MB ao mesmo tempo custava a você esse arquivo duas vezes. Agora o DuoUpdater percebe um download em andamento e o deixa em paz, avisando isso na linha em vez de simplesmente não fazer nada em silêncio. Se esse download acabar abandonado, ele deixa de contar depois de dez minutos, para que nada fique bloqueado.

**Uma atualização que um app já preparou não é mais sobrescrita.** Apps que se atualizam sozinhos costumam baixar em segundo plano e depois esperar você fechá-los para colocar a versão nova no lugar. Instalar por cima de uma dessas parecia funcionar e se desfazia no momento em que você fechava o app — e, quando a versão pendente do próprio app era mais antiga do que a que o DuoUpdater tinha acabado de instalar, você terminava mais atrasado do que quando começou. Agora essas atualizações são deixadas para terminar, seja qual for a versão que trazem.

**As atualizações do próprio DuoUpdater também ficaram menores.** Os lançamentos dele agora trazem o mesmo tipo de patch, então atualizar a partir de uma versão recente baixa algumas centenas de kilobytes em vez de onze megabytes.

## 0.3.61

**As explicações deixadas por uma atualização agora se apagam sozinhas.** Quando o DuoUpdater entrega um app ao próprio atualizador dele, a linha avisa — “foi trazido para a frente para que o atualizador dele aplique a atualização”. Essa frase ficava ali para sempre: a única coisa que a removia era começar outra atualização do mesmo app, então ela continuava embaixo da linha muito tempo depois de a atualização ter entrado, descrevendo algo que tinha terminado horas antes. Agora ela some assim que o app fica em dia. Um aviso de que uma atualização foi aplicada sem ponto de reversão é deixado de propósito, porque ele descreve a atualização que já aconteceu e só passa a importar depois que ela termina.

**Uma atualização recusada agora se explica no seu idioma.** Quando outra coisa já está instalando — o DuoUpdater trabalhando num lote, ou o `duo` num terminal —, a linha avisa. Essa mensagem só existia em inglês, numa janela de resto traduzida, e terminava com um número de processo: útil num terminal, e nada com que você possa fazer algo num menu. Agora ela é traduzida e diz o que fazer, em vez de quem está com o bloqueio. A ferramenta de linha de comando continua mostrando o número do processo, onde dá para fazer algo com ele.

**A linha do padrão de lançamentos, e o horário dela, agora seguem a sua região.** Registro de Versões → Padrões resumia tudo como “Most often ships Friday, around 6 PM”. Idiomas que flexionam os nomes dos dias não conseguem dizer isso com o dia encaixado no meio da frase, e acabavam com a forma errada da palavra — o russo mostrava “Чаще всего выходит пятница” quando precisa de “по пятницам”. Agora é um rótulo: “Pico: sexta-feira, por volta de 18:00”, que fica correto em qualquer idioma. O horário vai junto — se o seu Mac escreve as horas no formato de 24 horas, isto também escreve, inclusive no eixo do gráfico.

**A busca dos Ajustes agora entende as palavras que estão na sua tela.** O campo de busca acima da barra lateral dos Ajustes comparava com uma lista de termos extras escrita em inglês e nunca traduzida, então “rollback” levava a Geral, enquanto “Zurücksetzen” e “回滚” não levavam a lugar nenhum. Agora esses termos existem em todos os idiomas que o DuoUpdater fala. Os termos em inglês continuam funcionando em todos os idiomas também, já que a documentação de onde vêm está em inglês.

## 0.3.60

**Ativar “Mostrar tudo” não faz mais o menu hesitar.** A lista completa de todos os seus apps era medida por inteiro a cada vez que aparecia — num Mac com 127 apps, isso dava cerca de um segundo de trabalho, quase todo gasto organizando linhas bem abaixo das que você consegue ver. E o custo se repetia a cada vez que a opção era ativada, não só na primeira. Agora só as linhas que estão de fato na tela são montadas.

**Uma explicação que sobrou de uma atualização que falhou não dura mais do que a falha.** Quando uma atualização não podia ser aplicada — porque outra coisa já estava instalando, por exemplo —, a linha dizia o motivo, em vermelho. Nada jamais removia essa linha: quando a atualização finalmente entrava e a linha voltava a mostrar o sinal de visto, a explicação antiga continuava embaixo, e ficava ali a cada nova verificação até o DuoUpdater ser reiniciado. Agora ela some assim que o app fica em dia. Os motivos que pertencem a atualizações ainda pendentes são deixados em paz, para que um que você ainda não leu não seja apagado por uma verificação rodando em segundo plano.

**O botão “Atualizar Tudo” não muda mais de tamanho conforme o comprimento da lista.** Com poucas atualizações pendentes, ele era desenhado um tamanho menor do que deveria, com oitenta pontos de espaço vazio ao lado, e voltava ao tamanho certo sempre que a lista crescia. Agora ele fica sempre do tamanho que deve ter.

## 0.3.59

**O Tráfego de Downloads agora diz para qual build uma atualização foi, e não só para qual versão.** Muitos apps lançam vários builds com o mesmo nome de versão — o Surge lançou quatro versões diferentes como “6.9.0” —, então essas linhas mostravam “6.9.0 → 6.9.0” e não diziam nada. Agora elas mostram “6.9.0 (12028) → 6.9.0 (12030)”, e só quando o nome da versão sozinho não basta; quando a versão já mudou, o número de build seria só ruído e fica de fora.

**O build registrado é o que de fato entrou, lido no próprio app depois que a atualização está no lugar.** Não o número anunciado pelo feed de atualização do desenvolvedor — feeds às vezes informam errado, e assim funciona também para as fontes que não publicam número de build nenhum: GitHub, Homebrew e a App Store. Uma atualização que ainda está esperando na janela do instalador do macOS nunca é adivinhada; nada é registrado para ela até que seja real.

**Um download que não mudou nada agora é marcado como tal.** De vez em quando, uma atualização baixa e instala o build que já estava no seu Mac — um número de versão desencontrado do lado do desenvolvedor, um espelho servindo o que você já tem. Isso é banda de verdade gasta sem resultado nenhum, e a janela de tráfego é onde você iria querer ver isso. Essas linhas agora têm uma etiqueta “sem mudança”. Os downloads registrados antes desta versão não têm números de build para comparar, então são deixados como estão em vez de adivinhados: desconhecido não é o mesmo que inalterado.

## 0.3.58

**O DuoUpdater agora mostra quanto manter seus apps em dia realmente custou em downloads.** Ele vinha contando, byte a byte, cada atualização que baixou para você — mas a contagem não tinha onde aparecer, então o número ficava num arquivo que ninguém conseguia ler. Agora existe uma janela Tráfego de Downloads, aberta pelo botão de gráfico na parte de baixo do menu, com o total deste mês impresso ao lado desse botão, para que a pergunta mais comum seja respondida sem abrir nada. Lá dentro: o total, os últimos três meses lado a lado com a variação entre eles, um detalhamento de onde vieram os bytes e todos os apps classificados pelo quanto custaram — clique num deles para ver cada atualização que ele recebeu, de qual versão para qual versão foi e o tamanho do download.

**O total é honesto sobre o que não consegue ver.** O Homebrew, a App Store e os apps que se atualizam pelo próprio atualizador interno baixam os próprios bytes, e o DuoUpdater nunca passa por eles — então o número é um piso, não uma contabilidade completa. Isso sempre foi verdade; o que mudou é que a janela agora diz isso de forma permanente, e não só na tela vazia que você vê antes de qualquer coisa ser registrada.

**Apps que você renomeou ou apagou mantêm o histórico.** O tráfego é registrado pelo local em que o app fica no disco, e é isso que permite que dois canais do mesmo app — Android Studio Canary e Beta, por exemplo — fiquem separados em vez de somados. O preço é que renomear um app deixa o passado dele sob um nome que não existe mais. Quando a OpenAI renomeou o Codex para ChatGPT, isso dividiu 30 GB de downloads entre duas entradas que pareciam duplicadas. Agora essas entradas ficam agrupadas e esmaecidas no fim da lista, sob um título que diz o que elas são. Nada é descartado, e o total continua incluindo essas entradas.

## 0.3.57

**Um app que você instalou pela App Store não recebe mais a oferta do download do próprio desenvolvedor.** Muitos apps são publicados em dois lugares ao mesmo tempo — na loja e como download direto no site do desenvolvedor — com a mesma identidade, mas como builds realmente diferentes. O download direto costuma sair na frente, porque não espera a revisão da loja. O DuoUpdater verifica primeiro a loja para um app instalado por ela, mas, quando essa verificação falhava por qualquer motivo — uma conexão que caiu, uma loja regional que não respondeu —, ele passava silenciosamente para o site do desenvolvedor e oferecia o que estivesse lá. O WhatsApp mostrou isso como “26.32.75 → 26.33.19”: uma versão real, do lugar errado. Aceitá-la teria substituído a sua cópia da loja por uma que a App Store nunca mais conseguiria atualizar. Os apps instalados pela loja agora são verificados só na loja, e em nenhum outro lugar.

**Trocar o canal de atualização de um app dentro do próprio app agora é percebido na hora.** Alguns apps deixam você escolher entre as versões normais e as beta — Surge, Tailscale, Fork, OrbStack, IINA, Alfred e outros — e o DuoUpdater segue o que você escolheu, para nunca oferecer um build que você não pediu. Antes, ele só percebia a mudança quando você fechava o app ou abria uma das janelas do DuoUpdater. Nenhuma das duas coisas cobre o que as pessoas realmente fazem: desativar a opção, deixar o app aberto e dar uma olhada na barra de menus. Pior: os apps gravam essa opção no disco quando lhes convém, não no momento em que você clica — o Surge levou cinco minutos aqui —, então até fechar o app podia ser lido cedo demais. Agora o DuoUpdater observa a própria opção mudar e verifica aquele app de novo em um ou dois segundos. Voltar o Surge para as versões normais agora limpa a versão beta da linha dele na hora, em vez de deixá-la ali por até uma hora.

**Uma verificação que não conseguiu alcançar nada não parece mais um atestado de que está tudo bem.** Quando todas as fontes falhavam — sem rede, ou um proxy recusando conexões em silêncio enquanto o ícone do Wi-Fi continua dizendo que está tudo certo —, os apps que falharam eram escondidos e o painel dizia “127 apps · atualizados”. É a mesma tela que você vê quando tudo realmente está em dia, o que tornava uma verificação que falhou impossível de distinguir de uma bem-sucedida. Agora o painel diz quantos apps ele não conseguiu alcançar, mostra o que deu errado e oferece tentar esses de novo — só esses, deixando em paz tudo o que ele conseguiu verificar.
