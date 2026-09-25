# Novità

Questa è la traduzione di `CHANGELOG.md`. In caso di differenze fa fede la versione inglese. Le versioni non elencate qui vengono mostrate automaticamente in inglese.

## 0.4.5

**Blender scaricato da blender.org ora riceve gli aggiornamenti, con un clic.** Prima veniva controllata solo una copia installata con Homebrew.

**Le build alpha, beta e release candidate (RC) di Blender seguono il proprio canale.** DuoUpdater riconosce che tipo di build hai e ti avvisa quando ne esce una più recente dello stesso tipo. A una alpha non viene mai proposta una versione stabile, né viceversa.

**Gli aggiornamenti di Muse tornano a comparire.** Da quando Muse chiede di accedere per il suo link di download, la sua riga mostrava un errore invece della nuova versione.

**Dietro le quinte.** Il popover della barra dei menu e il banco di lavoro si aprono un po’ più in fretta la prima volta dopo l’avvio, e `duo check` ora elenca le app il cui controllo non è riuscito invece di dire che è tutto aggiornato.

## 0.4.4

**DuoUpdater ora parla italiano, cinese tradizionale, portoghese (Brasile) e turco.** In tutto sono undici lingue. In tedesco, spagnolo e giapponese sono stati corretti testi sbagliati o troncati. Impostazioni → Cartelle ora mostra i nomi delle cartelle come li mostra il Finder nella tua lingua.

**Le app che hai installato con Homebrew ora si aggiornano tramite Homebrew.** Riguarda le app installate con brew che hanno anche un proprio sistema di aggiornamento. Prima DuoUpdater le aggiornava direttamente senza che Homebrew lo sapesse, e il `brew upgrade` successivo scaricava e reinstallava la versione che avevi già.

**Le finestre si aprono nello Space in cui ti trovi.** Prima, riaprire Impostazioni o un’altra finestra di DuoUpdater dopo averla chiusa poteva riportarti nello Space in cui era stata mostrata l’ultima volta.

**Un aggiornamento, una notifica.** Alcune app vengono controllate tramite due fonti, che potevano annunciare la stessa nuova versione più e più volte.

**Il Registro release non mostra più release con una data nel futuro.** Se il feed di uno sviluppatore indica una data successiva al momento in cui DuoUpdater ha visto la release per la prima volta, il registro usa quel momento.

**Con il disco di backup scollegato, la finestra del banco di lavoro torna a stare nello schermo e Copia ora ti dice perché non può copiare.** Prima la finestra poteva diventare più alta dello schermo, così gli elenchi non scorrevano fino in fondo, e Copia ora non faceva nulla senza dire niente.

## 0.4.3

**Le beta e le release candidate di Xcode ora si aggiornano con un clic.** Accedi una sola volta al tuo account Apple Developer in Impostazioni → Xcode e DuoUpdater scaricherà e installerà le nuove beta e RC come qualsiasi altro aggiornamento. Prima poteva solo avvisarti che ne era uscita una nuova.

**Installa qualsiasi versione di Xcode accanto a quelle che hai già.** Impostazioni → Xcode elenca tutte le release di Xcode, raggruppate per versione, con il gruppo del tuo macOS già aperto. Installa mette quella che scegli nella cartella Applicazioni come copia a sé (per esempio Xcode-26.6.app) e non sostituisce nulla. Puoi anche salvare solo l’archivio (.xip). Se hai effettuato l’accesso, viene inclusa anche la lista di Apple, così le nuove release compaiono nel giro di pochi minuti.

**L’accesso ad Apple Developer si mantiene attivo da solo.** Apple chiude una sessione sviluppatore dopo circa otto ore. Ora DuoUpdater ne ottiene una nuova in background, senza finestre e senza password, finché Apple continua a riconoscere questo Mac. Puoi disattivare questa funzione in Impostazioni → Xcode.

**Le nuove release di Xcode compaiono prima.** Nei giorni feriali, nelle ore in cui Apple di solito pubblica, DuoUpdater cerca un nuovo Xcode ogni cinque minuti.

**Alcune app funzionano di nuovo dopo le modifiche dei loro sviluppatori.** CapCut beta e Superconductor nightly vengono di nuovo trovate e installate, e Superconductor mantiene la sua identità di app attuale. VLC 3.0.24 e JetBrains Air mostrano di nuovo le loro note di rilascio.

## 0.4.2

**Qoder CN IDE ora è supportato.** L’edizione per la Cina continentale dell’IDE di Qoder ha il controllo degli aggiornamenti, l’installazione con un clic e le sue note di rilascio nella finestra. Anche Qoder CN, l’app desktop, ora mostra le sue note di rilascio.

**Qoder IDE non cambia più idea sull’ultima versione.** Qoder distribuisce gli aggiornamenti in modo graduale, e ora DuoUpdater li chiede allo stesso modo della tua copia dell’IDE, così riceve ogni volta la stessa risposta. Prima la versione proposta poteva alternarsi tra due release, e un’installazione con un clic poteva fermarsi a metà perché la risposta era cambiata.

**Le app Sparkle che avevano scaricato un aggiornamento ormai superato si possono aggiornare di nuovo.** Se un’app che si aggiorna da sola tramite Sparkle aveva scaricato una build e in seguito ne è uscita una più recente, ora DuoUpdater elimina il vecchio download e installa l’ultima. Prima Aggiorna continuava a dire che l’installazione sarebbe stata annullata, e la riga non cambiava mai.

**`duo install` ti avvisa quando l’ultima build è già pronta.** Se il programma di aggiornamento dell’app ha già scaricato l’ultima versione, ora lo segnala e suggerisce di chiudere l’app o di eseguire `duo restart`. Prima diceva, sbagliando, che l’app si poteva solo controllare e non installare.

## 0.4.1

**搜狗输入法 ora si aggiorna con un clic.** DuoUpdater lo aggiorna come fa il metodo di input stesso, lasciando al suo posto il bundle installato, e prima salva una copia del tuo dizionario e delle tue impostazioni, così un ripristino riporta indietro anche quelli.

**I backup su un altro disco ora conservano il dizionario e le impostazioni di un metodo di input.** Prima sul disco dei backup veniva spostata solo l’app, quindi ripristinando da lì un metodo di input restavano i dati della versione più recente.

**Niente più aggiornamenti impossibili da installare.** JetBrains Air ora mostra la build che Toolbox offre davvero. Un’app dell’App Store rimasta con il vecchio nome dopo che lo sviluppatore l’ha rinominata ora ti dice quale copia aggiorna l’App Store, invece di proporre un aggiornamento che reinstalla soltanto l’altra copia.

**Le note di rilascio di altre app vengono mostrate formattate.** Le app che pubblicano le note in Markdown ora hanno lo stesso elenco nativo di tutte le altre. Prima le note comparivano come testo semplice.

## 0.4.0

**Riapri non entra più in conflitto con il programma di installazione di un’app.** Quando un’app ha scaricato da sé il proprio aggiornamento e il suo backup di ripristino va su un disco esterno, ora quella copia aspetta che il programma di installazione abbia finito. Prima veniva eseguita proprio nei pochi secondi che macOS concede al programma di installazione per fare il suo lavoro.

## 0.3.99

**I backup di ripristino ora possono stare su un altro disco.** Un backup è una copia completa di un’app, e sul volume di avvio finiscono per occupare parecchio. Impostazioni → Backup elenca i dischi collegati con lo spazio disponibile su ciascuno, sposta i backup che hai già e scrive lì quelli nuovi in background: se scolleghi il disco, il backup viene solo rimandato, non perdi un punto di ripristino. `duo backups` ha ora i comandi `disks`, `sync`, `verify` e `probe`.

**千问输入法 ora è supportato.** DuoUpdater ti avvisa quando esce una nuova versione e la aggiorna come fa il metodo di input stesso.

**Le note di rilascio non restano più bloccate sulla versione precedente.** Quando uno sviluppatore pubblicava un aggiornamento qualche minuto prima che la sua pagina del changelog lo citasse, le note precedenti venivano archiviate sotto la nuova versione e ci restavano per sempre. CleanShot X mostrava le note della 5.0 sotto la 5.0.1 dal giorno della sua uscita.

**Eliminare un backup ora libera davvero lo spazio indicato.** I backup creati dalle versioni precedenti di DuoUpdater venivano scritti in una forma che macOS si rifiuta di eliminare, quindi Pulisci lasciava su disco gran parte della copia pur contandola come spazio recuperato.

**Pulisci si apre subito.** Prima, ogni volta che lo premevi, ricalcolava da zero le dimensioni di tutti i backup salvati.

**WorkBuddy mostra di nuovo la sua versione più recente.** Il suo servizio di aggiornamento risponde con il passo successivo di una catena di aggiornamenti anziché con la build più recente, quindi tutte e quattro le edizioni di WorkBuddy restavano indietro di due release.

**Dietro le quinte.** Per le app che non dichiarano quale binario eseguono, tra cui Muse di Meta, ora framework e SDK vengono letti comunque.

## 0.3.98

**Gli aggiornamenti completati con Riapri ora si possono annullare con un ripristino.** Quando un’app ha già scaricato il proprio aggiornamento e premi Riapri, ora DuoUpdater salva prima la versione attuale, così l’aggiornamento compare in Ripristino come tutti gli altri. Prima si potevano annullare solo gli aggiornamenti installati da DuoUpdater stesso.

**Scopri cosa ha cambiato un aggiornamento all’interno di un’app.** Per ogni app di cui è salvata una versione precedente, il banco di lavoro ha ora una vista Confronto bundle accanto a Note di rilascio: firma e permessi, versione minima di macOS, elementi in background e di login, librerie incluse e i file aggiunti, rimossi o cambiati di dimensione. `duo diff` fa lo stesso dal Terminale per due copie qualsiasi di un’app.

**Riapri ti avvisa quando il programma di aggiornamento di un’app non ha applicato l’aggiornamento.** Se l’app si chiude e l’aggiornamento non arriva mai, ora la riga lo segnala e continua a proporre Riapri. Prima l’indicatore di avanzamento si fermava senza dire nulla.

**Cherry Studio mostra di nuovo la sua versione più recente.** Dopo che Cherry Studio aveva rinominato i suoi download per Mac, DuoUpdater considerava come ultima una release più vecchia, quindi le copie recenti risultavano “aggiornate” e a quelle più vecchie veniva proposta proprio quella build.

**Gli aggiornamenti dell’App Store non si bloccano più dietro un helper che non risponde.** Quando l’helper di DuoUpdater smetteva di rispondere, l’aggiornamento restava fermo allo 0% e tutti gli aggiornamenti dell’App Store in coda dietro di esso aspettavano finché non chiudevi DuoUpdater.

**Aggiorna tutto non riapre più le app che hai ignorato.** Con “Riapri automaticamente le app aggiornate” attivo, alla fine di un gruppo di aggiornamenti poteva chiudere e riaprire un’app ignorata, o un’app di cui avevi saltato la versione scaricata.

**Tinycast e SuperCmd ora sono supportati.** DuoUpdater ti avvisa quando esce una nuova versione di Tinycast o della sua beta, e ora riconosce il SuperCmd open source originale insieme a SuperCmd 2. Ora compaiono anche le note di rilascio di Kimi Code.

**Le note di rilascio corrispondono alla versione proposta.** La pagina delle note di rilascio più recenti di VS Code risultava vuota, e subito dopo l’uscita di una nuova versione il pannello delle note poteva mostrare la release precedente.

**Il Registro release non aggiunge più la stessa release a ogni avvio.** App come Claude, Raycast e Cline ricevevano una voce duplicata ogni volta che DuoUpdater si avviava.

**La barra laterale del banco di lavoro è divisa nelle schede App, Brew e Ripristino.** Fai clic su una scheda o trascina sopra di esse per passare dall’una all’altra; la ricerca filtra tutte e tre insieme.

**Dietro le quinte.** Riapri e Ripristina sulla stessa app non si sovrappongono più; un feed di aggiornamento non può più far eliminare a DuoUpdater file al di fuori della sua cartella di download; i controlli in background non rischiano più di far chiedere a macOS l’accesso ai dati di altre app; un numero molto grande nel filtro di Richieste non fa più chiudere l’app; e la barra dei menu ora rispetta la richiesta di password di amministratore che hai rifiutato in `duo install`.

## 0.3.97

**Gli aggiornamenti di iStat Menus vengono rilevati correttamente.** Quando iStat Menus ripubblicava un aggiornamento, DuoUpdater poteva continuare a proporlo anche dopo l’installazione, e premendo di nuovo Aggiorna si otteneva un errore.

**Memoh Desktop ora è supportato.** DuoUpdater ti avvisa quando esce una nuova versione e può aggiornarlo con un clic.

**Aggiorna tutto non ti chiede più di riaprire un’app dell’App Store che si è già riaperta.** Quando l’App Store chiude un’app e la riapre con la nuova versione, la sua riga ora la mostra subito come aggiornata, invece di indicare “Riapri ora” fino alla fine dell’intero gruppo.

## 0.3.96

**Un’app che ha già scaricato il proprio aggiornamento non lo riceve più due volte.** Alcune app scaricano un aggiornamento in silenzio in background e poi aspettano che tu le riavvii. Se premi Aggiorna in DuoUpdater, ora viene installata la copia che si trova già sul tuo disco: l’aggiornamento arriva in pochi secondi e non richiede alcun download. Prima DuoUpdater scaricava di nuovo la stessa release da capo.

**Cua Driver e Petex ora sono supportati.** DuoUpdater ti avvisa quando uno dei due ha una nuova release, e Cua Driver si aggiorna anche con un clic e mostra le sue note di rilascio.

**Lo stesso aggiornamento non ti viene più notificato di continuo.** Quando il server di uno sviluppatore continuava ad alternare due versioni, ogni controllo sembrava un nuovo aggiornamento e generava un’altra notifica.

**Un pacchetto appena installato non propone più di essere installato di nuovo.** La sua riga continuava a dire che il pacchetto scaricato sarebbe stato riaperto.

**DuoUpdater ora richiede macOS 15 Sequoia o versioni successive.** Un Mac ancora su macOS 14 mantiene la versione che ha e non riceve più aggiornamenti; ogni Mac con Apple silicon può passare a una versione di macOS supportata.

**Dietro le quinte.** I controlli ordinari non cercano più in anticipo i link di download: questo poteva nascondere per qualche istante un pulsante Aggiorna funzionante ogni volta che il server di download di uno sviluppatore andava in timeout.

## 0.3.95

**Aside ora è supportato.** DuoUpdater ti avvisa quando esce una nuova build del browser Aside e ne mostra le note di rilascio.

**Gli aggiornamenti che il tuo macOS non può eseguire non vengono più proposti, e ora la riga spiega il perché.** Quando uno sviluppatore indica le versioni di macOS supportate da una release, DuoUpdater ne tiene conto: dopo un aggiornamento di macOS, Little Snitch non propone più una build limitata a sistemi precedenti al tuo; Xcode non propone più una build che richiede un macOS più recente del tuo; e un pacchetto di installazione la cui app richiede un macOS più recente viene rifiutato, invece di installare un’app che non si aprirà. Le righe che prima mostravano un trattino ora indicano “Non ancora per questo macOS” o “Serve un macOS più recente”, con i dettagli a un clic di distanza.

**Scopri con quale SDK è stata compilata ogni app.** Fai clic sul simbolo accanto al nome di un’app e i dettagli ora indicano, per esempio, “Creata con l’SDK macOS 27.0.”: utile per capire quali app sono state ricompilate per l’ultima versione di macOS.

**Le app di Homebrew distribuite in due pacchetti, uno per i sistemi meno recenti e uno per il più recente, ora vengono lette da quello giusto.** OnyX si divide così per macOS 27, e DuoUpdater guardava solo il pacchetto pensato per i sistemi meno recenti: o non mostrava nulla per OnyX, o lo dava per aggiornato rispetto a una versione che Homebrew si rifiuta di installare su 27. Ora DuoUpdater segue quello dei due che hai installato.

**Le beta di TestFlight non perdono più il loro aggiornamento quando TestFlight si avvia.** Una beta con una nuova build in attesa poteva tornare a risultare “aggiornata” e restare così finché non riaprivi TestFlight.

**Gli aggiornamenti con un clic di Dropbox e ToDesk scaricano il file giusto.** Sui Mac con Apple silicon, Dropbox scaricava la build solo Intel, che poi il controllo di sicurezza rifiutava; a ToDesk veniva proposta la build in accesso anticipato che distribuisce solo ad alcuni utenti, invece della release generale.

**Riapri completa subito l’aggiornamento di Spotify.** Quando Spotify aveva già scaricato il proprio aggiornamento, Riapri restava in attesa per minuti prima che l’aggiornamento andasse a buon fine.

**Le build beta passano alle rispettive release.** A una beta di Xcode viene proposta la sua release candidate invece di risultare aggiornata, le beta di CotEditor vedono le sue release candidate, e a una beta di Carbon Copy Cloner il cui ciclo di test è terminato viene proposta la release in cui si è trasformata, invece di un controllo non riuscito.

**Le note di rilascio corrispondono alla versione che hai.** Blender 5.2 mostrava le note della 5.1, e Raycast 1.x mostrava quelle della 2.x. “Apri pagina” di Gemini ora apre l’attuale pagina desktop di Google invece di un errore.

**Le Impostazioni spiegano ogni opzione proprio accanto a essa.** Le lunghe note sotto intere sezioni sono sostituite da una breve riga sotto ogni controllo, e i menu di selezione descrivono solo l’opzione che hai scelto.

**Ora l’app scrive il suo nome DuoUpdater**, come sul sito web.

## 0.3.94

**I pacchetti Homebrew provenienti da tap che non hai contrassegnato come attendibili compaiono di nuovo.** Da Homebrew 6, brew salta in silenzio i pacchetti dei tap non attendibili quando elenca ciò che è installato, quindi erano spariti da DuoUpdater senza spiegazioni. Ora sono elencati come “Non controllata · tap non attendibile”, con il comando `brew trust` pronto da copiare; e appena lo esegui nel Terminale (o esegui un aggiornamento), la finestra si allinea non appena torni a DuoUpdater.

**Le app che richiedono una password di amministratore per aggiornarsi non vengono più aggiornate due volte.** Quando un’app come Tailscale aveva già scaricato il proprio aggiornamento ed era in attesa di un riavvio, DuoUpdater non se ne accorgeva e continuava a proporre Aggiorna, che poteva entrare in conflitto con il programma di installazione dell’app stessa. Ora la riga propone invece Riapri, e Aggiorna tutto la lascia stare.

**La sezione Homebrew ora può aggiornare Homebrew stesso.** Quando esce una nuova release di Homebrew, una riga in cima si offre di eseguire `brew update` per te. Resta nascosta se hai impostato `HOMEBREW_NO_AUTO_UPDATE`.

**Un aggiornamento di Homebrew non riuscito ora mostra l’errore reale di brew.** Prima la riga mostrava i consigli che brew stampa dopo l’errore, oppure niente, quindi un messaggio come “your Command Line Tools are too outdated” non ti arrivava mai. Inoltre, aggiornando più pacchetti insieme, non viene più segnalata la fine prima che l’operazione sia davvero terminata.

**L’icona nella barra dei menu conta oltre 50.** Con più di 50 aggiornamenti in attesa, prima restava ferma a 50.

**Note di rilascio: quelle di Claude sono raggruppate in Novità, Miglioramenti e Correzioni, come le mostra Claude stesso; quelle di Mac Mouse Fix compaiono come testo invece che come pagina incorporata; e l’app di Homebrew ora ha le sue note.**

**`duo check` non dice più “Everything is up to date.” quando in realtà non è riuscito a controllare.** Ora lo segnala quando non è riuscito a leggere TestFlight o quando la scansione delle app è stata interrotta.

## 0.3.93

**Le note di rilascio ora compaiono nella tua lingua quando un’app le pubblica in più lingue.** Alcune app distribuiscono le note tradotte insieme a ogni release; DuoUpdater prendeva la traduzione che l’app elencava per prima o per ultima, così le note di un’app erano in tedesco per tutti e quelle di un’altra cambiavano lingua da una release all’altra.

**Le app che hanno aggiunto una versione per Mac non risultano più “non supportate su questo Mac”.** Un’app per iPhone o iPad che usi su un Mac con Apple silicon veniva segnalata per errore nel momento in cui lo sviluppatore pubblicava una vera build per Mac, cioè proprio il cambiamento che rende l’aggiornamento più disponibile, non meno.

**Un’app dell’App Store di cui testi anche la beta non viene più scambiata per una build di TestFlight.** Quando uno sviluppatore promuoveva una beta senza modificarla, le due avevano lo stesso numero di build e la tua copia acquistata veniva assegnata a TestFlight, così l’App Store non poteva mai proporle un aggiornamento.

**Un aggiornamento dell’App Store che richiede un macOS più recente di quello che usi ora lo segnala.** Prima la riga proponeva comunque di installarlo e l’App Store lo rifiutava all’ultimo passaggio, senza che nulla sullo schermo spiegasse il perché.

**La finestra Richieste ora mostra fin dove arriva davvero il suo registro e segnala gli intervalli di date che non riesce a coprire del tutto.** Prima, scegliere “Ultimi 30 giorni” su un registro che risaliva solo a poche ore prima sembrava identico a scegliere “Ultime 24 ore”, senza che nulla sullo schermo spiegasse il perché.

**Scegli tu quanto DuoUpdater debba occuparsi delle beta di TestFlight, in Impostazioni → Generali.** *Quando ricarico* legge ciò che TestFlight sa già e gli chiede una risposta aggiornata quando premi il pulsante di ricarica; *Mantieni aggiornato* permette anche a DuoUpdater di chiedere di sua iniziativa, così una beta che TestFlight ha installato in background non resta più con un punto interrogativo finché non ricarichi, e una build che ti aspetta non passa più inosservata dietro un “aggiornato”; *Disattivato* non legge nulla e lo dice su quelle righe invece di tirare a indovinare. I Mac che avevano già l’Accesso completo al disco partono da *Quando ricarico*, tutti gli altri da *Disattivato*.

**Ora basta aprire TestFlight di persona perché DuoUpdater si accorga di ciò che ha installato.** Una beta installata tramite TestFlight restava con un punto interrogativo fino alla ricarica successiva, e su macOS 27, dove l’avviso “Pronta per il test” di TestFlight non arriva più per le app che hai già, potevano passare ore.

**Cline ora riceve aggiornamenti, sia per le build di release sia per quelle beta, e mostra le sue note di rilascio.** Finora restava con un punto interrogativo al posto della versione: non pubblica un feed di aggiornamento di un tipo che DuoUpdater sappia leggere, e non esiste un pacchetto Homebrew per Cline. Ora DuoUpdater interroga lo stesso indirizzo che usa il programma di aggiornamento di Cline, così l’aggiornamento proposto è quello che Cline avrebbe installato da sé, e la build beta resta sulla linea beta.

**Le note di rilascio che raggruppano le modifiche sotto titoli come Added e Fixed ora mantengono quei titoli.** Prima tutti i gruppi venivano fusi in un unico elenco, quindi non si capiva quali modifiche fossero nuove funzioni e quali correzioni di bug.

**Mac Mouse Fix ora propone le sue release beta se hai attivato “Get Beta Versions” nelle sue impostazioni generali.** Prima DuoUpdater vedeva solo le release normali di Mac Mouse Fix, quindi una build beta passava inosservata fino all’uscita della versione normale successiva.

**Le app il cui numero di build è un semplice contatore non nascondono più le proprie release correttive.** Per un’app che indica una versione come 12.10 con build 282987, una release 12.10.1 risultava “già aggiornata”.

**Una nuova build di un’app che mantiene lo stesso nome di versione viene di nuovo notificata.** Dopo la notifica di una build, tutte quelle successive con lo stesso nome arrivavano in silenzio: la riga si illuminava e il badge la contava, ma non compariva mai alcun banner.

**“Aggiorna tutto” ora conta solo le app effettivamente aggiornate.** Un’app che apre il programma di installazione di Apple perché sia tu a completare l’operazione veniva contata come completata mentre la sua finestra era ancora aperta, quindi “2 app sono state aggiornate” poteva significare che non era ancora cambiato nulla.

**Un aggiornamento andato a buon fine ma che ha lasciato dei residui ora risulta installato, non “concedi Gestione app”.** La nuova versione era già in esecuzione mentre la riga ti mandava a Impostazioni di Sistema.

**Interrompere “Aggiorna tutto” ora interrompe anche il download in corso.** Prima un trasferimento di diversi gigabyte proseguiva fino alla fine, con fino a cinque tentativi, e solo allora si accorgeva di essere stato annullato.

**Le note di rilascio non si confondono più tra due app che condividono la stessa pagina del changelog, e restano attuali dopo un aggiornamento per le app che hanno una pagina di note per ogni versione.** Antigravity e Antigravity IDE potevano mostrare l’una le note dell’altra per un quarto d’ora; Thunderbird, WeChat, Opera e alcune altre continuavano a mostrare per un po’ le note della versione precedente dopo l’aggiornamento.

**La ricerca nell’elenco delle app ignora gli accenti, come già faceva la ricerca nelle Impostazioni.** Ora digitando “cafe” trovi “Café”.

**La pagina Diagnostica mostra una riga di stato per ogni canale di release.** Una regola beta o preview non funzionante restava nascosta dietro la regola stabile corrispondente, che funzionava.

**Una risposta “forbidden” di GitHub non viene più segnalata come limite di richieste.** Un repository diventato privato o un token privo di un’autorizzazione ti spingevano ad aggiungere un token che non sarebbe servito.

**Riapri non viene più proposto per un’app che si aggiorna da sola se la build in attesa è più vecchia di quella in esecuzione.**

**Dietro le quinte.** Installazioni, backup e controlli dei pacchetti non occupano più i thread su cui gira il resto dell’app, quindi il menu resta reattivo mentre sono in corso; il menu rimane fluido anche durante un download di grandi dimensioni; il Registro release conta ogni release che un produttore pubblica sotto lo stesso nome di versione; un backup di ripristino viene rifiutato anziché archiviato se mancherebbe dell’eseguibile dell’app; il primo avvio su un Mac nuovo non registra più falsi errori del database; `duo verify` e `duo reconcile` ora segnalano un changelog le cui voci sono andate perse e un indirizzo del programma di installazione che non funziona da giorni; un comando `duo` bloccato rinuncia alla scansione dopo venti secondi invece di restare appeso.

## 0.3.92

**Alcune app che si aggiornano da sole non sembrano più aggiornate quando è uscita una versione più recente.** Per le app le cui informazioni di aggiornamento stanno dietro un server di download lento ad aggiornarsi, DuoUpdater poteva continuare a vedere una versione più vecchia per giorni dopo una release.

**Le note di rilascio di Kimi ora compaiono in DuoUpdater.**

**Gli aggiornamenti di CodeEdit ora compaiono.** Una versione più recente di CodeEdit lasciava la sua riga con un punto interrogativo invece di proporre l’aggiornamento.

**Dietro le quinte.** L’elenco Homebrew nel menu si riempie più in fretta, e i comandi `duo` si avviano più velocemente.

## 0.3.91

**Controlla di nuovo su una beta di TestFlight ora dà la risposta reale.** Prima trasformava la riga in un punto interrogativo fino alla ricarica successiva.

**Le beta di TestFlight mantengono le loro risposte mentre il pulsante di ricarica verifica con TestFlight.** Per qualche secondo potevano trasformarsi tutte in punti interrogativi.

## 0.3.90

**super.engineering ora è supportato: controllo degli aggiornamenti, note di rilascio e installazione con un clic.** Una nuova nightly compare con le sue novità, e Aggiorna la installa per te.

**Microsoft Edge Beta poteva proporti una build stabile di Edge.** Mentre il feed beta di Microsoft era temporaneamente vuoto, la riga indicava una versione stabile, e aggiornando la si sarebbe installata sopra la tua beta.

**Le beta di TestFlight ora mostrano gli aggiornamenti che TestFlight ha per loro, comprese le beta di app per iPhone e iPad.** Il pulsante di ricarica verifica con TestFlight in background, un aggiornamento non sparisce più pochi minuti dopo che l’hai trovato, e il pulsante TestFlight apre la pagina di quella beta.

**Quando DuoUpdater non riesce a capire se una beta di TestFlight è aggiornata, lo dice.** La riga mostra un punto interrogativo invece di darla per aggiornata, per esempio quando non hai eseguito l’accesso a TestFlight o non partecipi più al test di quella beta.

**L’Accesso completo al disco ora viene spiegato, e senza di esso nulla ti tormenta.** Senza questo accesso, DuoUpdater non fa più scattare gli avvisi di macOS sulla lettura dei dati di altre app; se una beta di TestFlight o CotEditor ne ha bisogno, ti viene spiegato una sola volta perché e dove concederlo.

**Riapri scompare quando un’app aggiornata è stata chiusa.** Un’app che lasciava in esecuzione un processo helper continuava a chiedere di essere riaperta molto tempo dopo che il suo aggiornamento era entrato in vigore.

**Una richiesta di privacy di macOS rimasta senza risposta non blocca più il controllo degli aggiornamenti.** Il controllo prosegue senza l’impostazione di quell’app.

**Le note di rilascio di Rockxy e Ollama sono di nuovo complete.** Quelle di Rockxy ripercorrono le release recenti invece di mostrare solo l’ultima, e la release più recente di Ollama non viene più tralasciata.

**`duo`, lo strumento opzionale da riga di comando, gestisce meglio TestFlight.** `--refresh-testflight` funziona che TestFlight sia aperto o no, senza prendere il controllo dello schermo, e `duo check` non dà più per aggiornata una beta quando TestFlight ha annunciato una build più recente.

## 0.3.89

**Telegram Desktop ha di nuovo il controllo degli aggiornamenti.** Telegram aveva cambiato il nome del file che pubblica e la riga non riusciva più a leggerne la versione, quindi mostrava un controllo non riuscito invece dell’aggiornamento che c’era dietro.

**Una build TestFlight di un’app per iPhone o iPad viene riconosciuta come tale.** DuoUpdater la leggeva invece come un acquisto dall’App Store, quindi la riga indicava il gestore sbagliato mentre all’App Store veniva chiesta una scheda che non esiste, a ogni controllo, per tutto il tempo in cui l’app restava installata.

**Una beta di TestFlight è contrassegnata dall’icona di TestFlight.** Le righe gestite dall’App Store avevano già l’icona dello store; quelle gestite da TestFlight ne scrivevano invece il nome per esteso, quindi lo stesso tipo di riga era contrassegnato in due modi diversi.

**L’intestazione della finestra Rete resta ferma quando cambi scheda.** Le due schede avevano i titoli ad altezze leggermente diverse, quindi passando dall’una all’altra sembrava che la finestra avesse un sussulto.

## 0.3.88

**Scorrere l’intero elenco delle app è di nuovo fluido.** Uno scorrimento rapido dell’elenco completo perdeva fotogrammi; ora ogni riga comunica la propria altezza senza doverla prima costruire.

**Le note di rilascio di un’app dell’App Store ora arrivano sempre dall’App Store.** Quando la ricerca dello store per un’app non trovava nulla o non riusciva, la finestra poteva ripiegare sulle note dell’altra distribuzione di quell’app, una build diversa con i suoi numeri di versione, che descrivevano una release che alla tua copia non sarebbe mai stata proposta.

**A Windscribe sul canale Beta o Guinea Pig vengono proposte le build di quel canale.** DuoUpdater legge quale canale di aggiornamento hai scelto nelle impostazioni di Windscribe, quindi a una copia che segue una linea di pre-release non viene più detto che è aggiornata mentre su quella linea esistono build più recenti. La finestra mostra anche le note di quelle build di pre-release, che prima elencava solo per le build stabili.

**Windscribe ora ha il controllo degli aggiornamenti, con le sue note di rilascio.** Una copia con una build più vecchia viene elencata con la versione a cui può passare e le relative novità; prima DuoUpdater non aveva alcun modo di vedere la versione di Windscribe. L’aggiornamento si esegue comunque con il programma di installazione di Windscribe, che configura parti dell’app che si trovano al di fuori dell’app stessa.

**Un aggiornamento non viene più applicato a un’app sparita mentre facevi clic.** Se l’app viene disinstallata, sostituita o non è più leggibile tra il clic e l’inizio dell’installazione, ora DuoUpdater si ferma e lo segnala, invece di installare comunque in quella posizione.

**`duo`, lo strumento opzionale da riga di comando, non dà più per completata l’installazione di un pacchetto prima del tempo.** L’installazione di un’app distribuita come `.pkg` apre il programma di installazione di macOS e lascia a te il resto, ma il riepilogo la contava come installata: “1 installed” quando non era ancora stato sostituito nulla. Ora questi casi vengono contati a parte. Anche l’output `--json` indica per ogni riga cosa è successo a quell’app, così uno script non deve più leggere la spiegazione in inglese per distinguere un errore da un salto voluto.

**Dietro le quinte.** Il ricontrollo prima dell’installazione che protegge l’Aggiorna con un clic ora protegge anche `duo install`, e le verifiche che un download deve superare prima di sostituire un’app sono riunite in un unico punto per entrambi i percorsi che le usano.

## 0.3.87

**Fare clic su Aggiorna non resta più senza effetto quando una fonte di aggiornamento si contraddice.** Se il controllo eseguito nel momento del clic restituisce una versione più vecchia di quella che la riga proponeva, ora DuoUpdater lo segnala e mantiene l’aggiornamento disponibile. Prima dava l’app per già aggiornata e la toglieva dall’elenco, e lo stesso aggiornamento ricompariva al controllo successivo.

**Gli aggiornamenti di Fork vengono di nuovo proposti quando Fork è impostato sul canale Develop.** DuoUpdater leggeva al contrario l’impostazione del canale di Fork e seguiva il feed Stable, che è parecchio indietro, quindi una copia Develop risultava aggiornata mentre Fork stesso proponeva una versione più recente.

**Mac Performance Monitor ora mostra le sue note di rilascio.** L’app le pubblica nel suo repository anziché nel feed che leggiamo, quindi la finestra non aveva nulla da mostrare.

**CotEditor ora è coperto, sia sulla linea di release sia su quella beta.** La linea seguita da una copia dipende dalla versione in esecuzione e dall’impostazione “Update to prereleases when available” di CotEditor, così a una copia beta viene proposta la beta successiva invece di una release che la riporterebbe indietro.

**A un’app installata dall’App Store non viene mai proposto un download da un’altra fonte.** Quando la ricerca dello store per quell’app non riesce o non restituisce nulla, la riga ora indica che è gestita dallo store, senza numero di versione. Prima il controllo poteva ripiegare sull’altra distribuzione dell’app, una build diversa con i suoi numeri di versione, e proporre di installarla sopra la tua copia dello store.

**A un’app non viene mai proposto un aggiornamento che la porterebbe a una versione più vecchia.** Alcuni feed elencano una release stabile sopra una pre-release che in realtà è più avanti, e sceglierla avrebbe riportato l’app indietro.

**Un errore lungo su una riga non spinge più in basso il resto dell’elenco.** Viene limitato a due righe, con il testo completo al passaggio del puntatore.

## 0.3.86

**Altre quattro app coperte: WhatCable, Qoder IDE, Qoder e Yaak.** Ognuna ha il controllo degli aggiornamenti e l’installazione con un clic, e le loro note di rilascio vengono lette nella finestra come testo anziché come pagina incorporata.

**Le due app per Mac di Qoder vengono distinte.** L’IDE e l’app desktop condividono il nome e la pagina di download ma hanno linee di versione separate, quindi ora ciascuna viene seguita per conto proprio.

**Le build beta di WhatCable e Yaak vengono seguite su una linea propria.** Una copia con una beta non aveva alcuna fonte e restava su “Non riuscito”; ora le viene proposta la beta successiva, con note di rilascio tenute separate da quelle stabili. Per WhatCable questo comprende anche la release stabile in cui una beta alla fine si trasforma: scegliendola, la copia passa alla linea stabile.

## 0.3.85

**Il controllo delle app dell’App Store usa una frazione del traffico di rete di prima.** Ogni controllo scaricava di nuovo la pagina prodotto di ogni app dell’App Store; ora le pagine vengono conservate per un’ora e allo store si chiedono informazioni su tutte le tue app con poche richieste invece che con una per app. Con un intervallo di controllo di cinque minuti si risparmia circa un terzo del traffico complessivo; con l’intervallo predefinito di sei ore le pagine scadono comunque tra un controllo e l’altro, quindi il risparmio è minore.

**Ricontrollare una singola app non scarica più di nuovo tutte le app dell’App Store.** Un solo “Controlla di nuovo” eliminava tutte le pagine prodotto in cache, quindi il controllo programmato successivo doveva riscaricarle tutte; ora aggiorna solo l’app che hai chiesto.

**Il controllo delle app distribuite tramite GitHub usa una frazione del traffico di rete di prima.** Ogni controllo scaricava di nuovo la descrizione completa di ogni release anche quando non era stato pubblicato nulla; ora chiede a GitHub se la release è cambiata dall’ultima volta e non scarica nulla se non è cambiata. Una volta al giorno rilegge per intero ogni release, così una release ritirata viene notata entro un giorno.

**Le app seguite su una linea beta o nightly di GitHub ora chiedono una sola release invece di una pagina intera.** La release più recente è quasi sempre la risposta, e la pagina completa viene scaricata solo nelle volte in cui non lo è.

**Il controllo degli aggiornamenti di Vorssaint non passa più da un reindirizzamento.** Il suo repository era stato rinominato, e seguire il vecchio nome faceva finire la richiesta, senza avvisi, nel limite di richieste anonime di GitHub; ora il controllo va direttamente al nuovo nome.

**Dietro le quinte.** L’app pubblicata ora viene compilata, firmata e autenticata da Apple su un Mac ospitato da GitHub, con una provenienza della build verificabile da chiunque, e il registro delle richieste distingue una risposta dalla cache da una ottenuta dalla rete.

## 0.3.84

**I registri delle richieste che esporti non contengono più il nome del tuo account.** Ogni riga di un’app installata nella tua cartella Inizio riportava il percorso completo; ora mostra invece `~`, in qualunque modo esporti il registro.

**La scheda Richieste ora dice cosa copre e cosa no.** Registra le richieste di rete che DuoUpdater fa da sé. Una pagina di note di rilascio carica da sola immagini e font, e gli aggiornamenti dell’App Store e di Homebrew vengono eseguiti da strumenti separati: nulla di tutto ciò compare lì, e ora la finestra lo dice invece di lasciartelo supporre.

**Copia URL ora applica l’escape all’indirizzo che ti fornisce.** I percorsi con uno spazio, tra cui i download di Firefox, Thunderbird e Bartender, venivano copiati così com’erano, cosa che un browser perdona ma la riga di comando no.

**La riga beta di CapCut non segnala più un controllo non riuscito.** Tra una beta e l’altra, cioè dopo che una diventa definitiva e prima che si apra la successiva, il produttore non pubblica nulla su quella linea, e questo compariva come una riga rossa con un pulsante Riprova che non avrebbe potuto funzionare. Ora la riga semplicemente non ha una risposta da quella fonte finché non compare la beta successiva.

**Audacity ora mostra il simbolo che indica con cosa è stata realizzata.** Si avvia tramite un piccolo launcher che passa il controllo al programma vero e proprio che si trova accanto, e il simbolo veniva letto dal launcher, che non collega alcuna libreria.

**Le note di rilascio dell’App Store ora arrivano nella tua lingua.** Venivano sempre scaricate nella lingua predefinita dello store, quindi su un Mac in cinese o giapponese si leggevano comunque in inglese.

**Gli aggiornamenti di DuoUpdater stesso ora compaiono con il suo nome nella finestra Rete.** Il controllo delle release, le note di rilascio e il download venivano tutti registrati con la colonna dell’app vuota.

**Dietro le quinte.** Una credenziale contenuta nel percorso di un indirizzo web ora viene rimossa prima che la richiesta venga registrata, come è sempre successo per quelle nella query string.

## 0.3.83

**La finestra Traffico di download ora si chiama Rete e ha una seconda scheda.** Download è il registro che avevi già: quanto è costato ogni aggiornamento come file. Richieste è nuovo: ogni richiesta di rete che DuoUpdater fa per tuo conto, a cosa serviva, a quale app apparteneva e quanto è costata, con un campo filtro per interrogare il registro invece di scorrerlo. I valori in alto si riferiscono a ciò che hai filtrato, non al totale complessivo.

**Il controllo degli aggiornamenti di Spotify ora usa pochissimo la rete.** Spotify non pubblica da nessuna parte un file con la versione, quindi il controllo legge la versione da un piccolo programma di installazione da due megabyte, e lo scaricava per intero ogni volta, giorno e notte. Ora chiede se quel file è cambiato e salta il download se non lo è.

**PDF Expert ora trova i suoi aggiornamenti e mostra le novità.** Leggeva un elenco di release che il produttore ha smesso di aggiornare nel 2022, quindi si dava per aggiornato qualunque versione avessi. Ora segue l’elenco usato dal programma di aggiornamento dell’app, e riporta anche le note di rilascio delle versioni passate, non solo della più recente.

**Le build preview di UTM ora ricevono i propri aggiornamenti, si installano con un clic e mostrano le note di rilascio corrispondenti.** Una copia preview veniva confrontata con la linea definitiva e le si diceva, senza avvisi, che era aggiornata; ora segue la propria linea, e quando passa alla release definitiva di quella linea torna alla linea definitiva.

**Dietro le quinte.** Le richieste registrate sono state spostate nello stesso archivio del registro dei download, così i due resoconti di uno stesso download non possono più discostarsi. Il tuo registro esistente viene trasferito senza modifiche.

## 0.3.82

**Altre quindici app vengono tenute d’occhio per gli aggiornamenti, e tutte tranne una si installano con un solo clic.** AgentsView, AnythingLLM, Chatbox, ChatGPT Classic, DSH Desktop, FluidVoice, GitHub Copilot, Kun, Meetily, Microsoft 365 Copilot, OpenLogi, OpenSuperWhisper, Paseo, T3 Code (sia sulla linea alpha sia su quella nightly) e Vorssaint. L’eccezione è ChatGPT Classic: viene controllata per te, ma distribuisce un programma di installazione che aggiorna l’app stessa, quindi eseguirlo resta compito tuo.

**Otto app ora mostrano le loro note di rilascio in DuoUpdater invece di mandarti a una pagina web.** Xcode, Antigravity, Antigravity IDE, AnyDesk, AnythingLLM, Chatbox, Headlamp e Helium. Per tre di esse, in realtà, non c’era nemmeno una pagina a cui mandarti: la pagina di AnyDesk risponde con una verifica anti-bot, i produttori di Helium non pubblicano alcuna pagina di note, e Antigravity IDE non aveva alcun link.

**Le beta di Xcode dicono cosa è cambiato in ogni beta.** Prima la riga proponeva un numero di build e un link; ora elenca le note di Apple per la beta che usi e per tutte le beta precedenti di quella release.

## 0.3.81

**Word, Excel, PowerPoint, Outlook e OneNote ora si accorgono di quando il loro aggiornamento è andato a buon fine.** Queste cinque app continuavano a proporre di riaprire il programma di installazione che avevi già completato e non passavano mai a proporre il riavvio: né aspettare né ricontrollare avrebbe sbloccato la situazione.

**Una riga in attesa di essere riaperta spiega di nuovo il perché, in entrambe le finestre.** Quando un’app era sia più avanti di ciò che pubblica il produttore sia in attesa di essere riaperta, la riga sopra il pulsante descriveva tutt’altro; inoltre la finestra e il menu non erano d’accordo sulle righe in attesa di un riavvio dopo Aggiorna tutto.

**Le etichette delle righe non tolgono più spazio al nome dell’app in russo.** Inoltre alcune etichette prendevano in prestito la formulazione da stringhe non correlate in tutte le lingue tradotte.

**Ora compaiono le note di rilascio delle app il cui produttore indica la data di una release senza l’ora.** Queste release prima non lasciavano traccia da nessuna parte.

**Una pagina di note di rilascio che ci rifiutiamo di aprire ora spiega il perché.** Prima restava vuota, esattamente come quella di un’app che non pubblica alcuna nota.

**Le note di rilascio nightly di WeChat DevTools non sono più vuote.**

**Dietro le quinte.** La gestione delle versioni e delle date di rilascio è stata unificata, così un numero di build non può mai essere letto come versione commerciale, e la cronologia delle release non inventa più un orario che il produttore non ha mai indicato.

## 0.3.80

**I controlli non riusciti ora sono visibili nella finestra.** La finestra non mostrava nulla per una riga il cui controllo non era riuscito (o per una che avevi ignorato, una che avevi saltato, o una gestita dall’App Store, da Toolbox o da TestFlight), e il risultato sembrava identico ad “aggiornata”. Ora le due finestre dicono la stessa cosa sulla stessa app, e il pulsante Riprova c’è in entrambe.

**“Controlla di nuovo” su qualsiasi riga interroga solo quell’app.** Rilegge anche quali app sono in esecuzione, quindi è il modo rapido per correggere un pallino verde che sembra sbagliato.

**Saltare e ignorare ora funzionano dal menu contestuale della finestra.** Entrambe le righe ti dicevano di fare clic con il tasto destro per annullare, in una finestra il cui menu non aveva nulla del genere.

**Il controllo in background non ti toglie più le note di rilascio che stai leggendo.** Il controllo orario eliminava tutte le note già caricate, quindi un pannello Note di rilascio aperto tornava all’indicatore di caricamento. Ora solo una ricarica richiesta da te le fa ripartire da capo.

**I download interrotti vengono verificati prima di essere considerati completi.** Un server che rimandava l’intero file, o che si fermava prima della fine, veniva preso sulla parola, e il problema emergeva un passo dopo come un’installazione non riuscita su un archivio danneggiato. I download attraverso un proxy che prima fallivano sempre ora funzionano.

**Aggiornare un’app non ripete più la scansione di tutte le app sul disco.** Ogni clic eseguiva due passate complete su tutte le tue applicazioni per esaminare quella che avevi chiesto.

**Le note di rilascio di Chrome non possono più bloccarsi.** Bastava un normale restyling del blog di Google per bloccarle per minuti; ora si caricano subito, qualunque aspetto abbia la pagina.

**Un programma di installazione scaricato non viene più scartato e riscaricato.** Quando un produttore scriveva la stessa release in due modi (`v1.2.3` e `1.2.3`), il pacchetto in attesa non veniva riconosciuto e Riapri poteva continuare ad aspettare una sostituzione già avvenuta.

**Un’installazione come amministratore non riuscita non viene più scambiata per un tuo clic su Annulla.** Non veniva mostrato alcun errore, e quell’app smetteva in silenzio di proporre aggiornamenti con un clic finché non richiedevi di nuovo l’accesso come amministratore dal menu della sua riga.

**Il pallino verde “in esecuzione” ora si accorge di ogni app.** macOS non annuncia mai l’apertura o la chiusura di alcune app, e il loro pallino restava sbagliato finché qualcos’altro non lo aggiornava.

**“Aggiorna tutto” non compare e scompare più durante una ricarica**, e un’app che aggiorni durante una ricarica non torna a proporre l’aggiornamento che ha già installato.

**Un controllo che non riesce proprio mentre premi Aggiorna ora lo dice**, invece di essere archiviato come “niente da fare”.

**Dietro le quinte.** Le date di rilascio scritte in formati insoliti vengono lette correttamente, la verifica dell’indirizzo delle pagine di note di rilascio copre ogni grafia equivalente, e le normali operazioni interne non toccano più il disco ogni volta che un’app sul tuo Mac si apre o si chiude.

## 0.3.79

**Il simbolo di Docker ora descrive l’interfaccia di Docker invece del suo daemon.** La riga diceva “nativa”, ma Docker Desktop è un’app Electron. Il simbolo viene letto dal bundle dell’app, e il bundle di Docker è un involucro: il programma che indica è un servizio in background scritto in Go, non contiene alcun framework proprio, e l’app che disegna davvero le finestre si trova un livello più all’interno. Tutto veniva letto correttamente, ma dal file sbagliato. Ora DuoUpdater guarda nell’app annidata quando, e solo quando, quella esterna non contiene nulla di suo e contiene esattamente una di queste app che dimostra con cosa è realizzata; così un processo helper distribuito accanto a una vera interfaccia non può comunque prestare la propria identità all’app che lo contiene. Docker risulta Electron 42.5.0 e, delle centoquarantasei app presenti nell’elenco sul Mac su cui è stato scritto questo testo, è l’unica riga che cambia.

**Le note di rilascio di CleanShot X sono di nuovo leggibili, comprese quelle della 5.0.** CleanShot ha pubblicato la sua release più importante da anni e, insieme, ha ricostruito la pagina del changelog: la data è finita sopra il numero di versione, sono comparsi due nuovi livelli attorno, e una release con nuove funzioni ora mette un’introduzione e due link a video tra la versione e l’elenco delle modifiche. Il lettore usato da DuoUpdater non riconosceva più nulla di tutto ciò. Il peggio è che il pannello non sembrava vuoto: le note già salvate per la release precedente restavano sullo schermo sotto il titolo della nuova versione, quindi il pannello diceva “5.0” sopra le modifiche della 4.8.10 e niente da nessuna parte segnalava il contrario.

**Le note salvate prima della pubblicazione di una release ora vengono rilette invece di essere considerate definitive per sempre.** È l’altra metà della stessa storia. DuoUpdater sapeva dell’esistenza della 5.0 sei minuti prima che CleanShot ne pubblicasse il contenuto, ha salvato la pagina così com’era e l’ha archiviata sotto la 5.0; da quel momento ogni controllo trovava qualcosa di già salvato e non guardava più. Ora le note salvate vengono confermate con il produttore una volta per sessione prima di essere considerate definitive, così una versione le cui note arrivano in ritardo si completa alla visita successiva invece di restare sbagliata.

**Tutto ciò che apri dalla barra dei menu ora si apre al primo clic.** Scegliere Registro modifiche su una riga (o Impostazioni, o il Registro release) la prima volta non faceva nulla, e funzionava solo dal secondo clic in poi. Riaprendo il menu ogni tentativo tornava a essere il primo, quindi per chi apre il menu, fa clic una volta e si aspetta una finestra, non funzionava mai. Il primo clic nel menu veniva speso per portare DuoUpdater in primo piano invece di fare ciò a cui era destinato. Inoltre la finestra che si apre ora resta in primo piano: veniva portata davanti e subito rimandata indietro nello stesso istante, e questo era l’altro motivo per cui sembrava un clic che non faceva nulla.

## 0.3.78

**Un’app che lascia vuoto il proprio nome ora ne riceve comunque uno.** Eudic (欧路词典) compariva nell’elenco con un’icona, una versione e nulla al posto del nome. Il suo bundle dichiara un nome da mostrare, ma lo lascia vuoto perché i nomi veri si trovano nelle traduzioni dell’app, e DuoUpdater prendeva quella risposta vuota come definitiva invece di passare alla domanda successiva. Ora ripiega sull’altro nome dell’app e, dopo quello, sul nome del file dell’app, così una riga non resta mai senza nome. Qui era interessata un’app su centocinquanta; il punto è che l’informazione c’era già e veniva ignorata.

**Riapri ora ti dice quando l’app si è rifiutata di chiudersi, invece di sembrare un clic senza effetto.** Se un’app ha una finestra che ti aspetta (una richiesta di salvataggio, un foglio di accesso, un qualsiasi dialogo), macOS non le permette di chiudersi, e da questa parte non si può fare nulla: è una finestra dell’app. DuoUpdater restava in attesa per trenta secondi e poi rimetteva lo stesso pulsante senza spiegazioni, il che sembra esattamente un pulsante rotto, e così lo si premeva di nuovo. Ora la riga dice cosa è successo e ti indirizza all’app per gestire quella finestra. Non è cambiato nulla e la nuova versione è già installata, quindi manca davvero solo la riapertura; e se chiudi tu stesso l’app nei dieci minuti successivi, DuoUpdater se ne accorge e la riapre con la nuova versione senza che tu debba fare clic.

**Le note di rilascio di 欧路词典 sono di nuovo quelle di una release, non di sedici anni.** L’app pubblica tutta la sua cronologia, ogni versione fino alla 2.5.0, dentro le note della release più recente, quindi il pannello dei dettagli la mostrava tutta sotto il titolo “26.9.0” e dovevi scorrere oltre un decennio per trovare ciò che era appena cambiato. Ora ogni versione ha la sua voce nell’elenco, come per tutte le altre app.

**Il simbolo che indica con cosa è realizzata un’app ora richiede una prova per Tauri, non una somiglianza.** Tauri non lascia nulla da trovare in un bundle (nessun framework, nessuna cartella propria), quindi quel simbolo veniva dedotto dal modo in cui l’app era stata impacchettata, più il fatto che collega la web view di Apple. Longbridge corrisponde a tutto questo e non è Tauri: disegna le proprie finestre con lo stesso motore di rendering usato da Zed e incorpora una web view per un angolo della sua interfaccia. Ora DuoUpdater legge l’impronta di Tauri nel binario prima di dichiararlo, così un’app viene indicata come Tauri quando lo è davvero, e Longbridge risulta l’app nativa per Mac che è.

**CapCut non diventa più rossa perché i server di ByteDance hanno avuto un brutto mezzo secondo.** L’endpoint a cui DuoUpdater chiede la versione di CapCut risponde con un codice di successo e poi, circa una volta su cinquanta, con un oggetto di errore al posto della risposta: un timeout interno all’infrastruttura di ByteDance, circa 390 byte dove se ne aspettavano 436 kilobyte. Da questa parte non c’era modo di distinguerlo da un cambiamento nel formato della risposta di CapCut, quindi la riga diceva che il controllo non era riuscito, il che suona come “è rotto e qualcuno deve ripararlo” per qualcosa che si risolve da solo al tentativo successivo. Ora quella forma specifica viene riconosciuta per ciò che è: la richiesta viene ripetuta subito, e viene segnalata come problema reale solo se continua a verificarsi per cinque giorni.

## 0.3.77

**Ogni app nell’elenco ora indica con cosa è realizzata.** La riga di un’app dell’App Store ha sempre avuto il badge dello store, e tutte le altre righe erano uguali: un’app Sparkle, un’app Electron e una nativa erano indistinguibili. Ora ogni nome è accompagnato dal simbolo della tecnologia (fai clic per una parola e una frase di spiegazione, o passa sopra con il puntatore per il suggerimento): Electron, Tauri, Flutter, Qt, Java, Chromium, Mac Catalyst, un’app per iPhone su Apple silicon o un’app nativa per Mac, con la versione del runtime quando può essere letta come dato certo (Electron 42.4.1, Qt 6.2, il Chromium incorporato in un’app, il Tauri con cui è stata compilata). L’informazione viene letta dal bundle stesso (il framework che un sistema di pacchettizzazione ha dovuto includere, il runtime di cui ha bisogno un launcher, le librerie collegate dal binario), quindi è un dato su ciò che è installato e non un’ipotesi basata sul nome dell’app. Quando un nome lungo non lascia spazio, il simbolo si fa da parte invece di spingere il nome su una seconda riga: il nome è la riga. Puoi disattivare tutto in Impostazioni → Generali.

**LibreOffice non segnala più un downgrade alla versione che hai già.** Il suo indice dei download elenca versioni in tre parti (`26.8.0`), mentre la copia installata ne indica quattro (`26.8.0.3`), e completare la parte mancante con uno zero faceva sembrare più recente la copia installata; così la riga mostrava una nota attenuata del tipo “il produttore è più indietro di te” per un’app perfettamente aggiornata. Ora una fonte che pubblica meno parti di quante ne indichi l’app viene letta come riferita alla stessa release, non a una più vecchia; un vero ritorno a una versione precedente viene comunque segnalato.

**Un’impostazione aggiunta da un aggiornamento ora si segnala una volta.** Una nuova preferenza che compare nel mezzo della finestra Impostazioni è una preferenza che nessuno trova. Dopo un aggiornamento che ne ha aggiunta una, l’ingranaggio nella barra dei menu mostra un pallino blu, la pagina in cui si trova ne mostra uno nella barra laterale, e il controllo stesso ne mostra uno finché non lo hai visto. Solo per chi ha effettivamente aggiornato: una nuova installazione non viene accolta con pallini su funzioni che fanno semplicemente parte dell’app appena conosciuta.

## 0.3.76

**Le app con manifest Electron aggiunte nella release precedente ora si possono davvero aggiornare.** La 0.3.75 aveva insegnato a DuoUpdater a leggere il file che quelle app contengono al loro interno, e lo leggeva davvero: ricavava la nuova versione, il download giusto per il tuo Mac e il checksum con cui verificarlo, e poi non aveva dove mandare nulla di tutto ciò. Il pulsante di installazione non compariva mai, e `duo install` spiegava il rifiuto con un motivo che non era quello vero. In questa release il percorso di installazione è collegato. In pratica potresti non notare alcuna differenza: questo lettore viene dopo tutte le regole scritte a mano, quindi interviene solo per un’app che nient’altro copre, e oggi, sul Mac su cui è stata preparata questa release, non ce n’è nessuna. Conta per l’app che installerai domani e per cui nessuno ha ancora scritto una regola.

**Un download che ti farebbe abbandonare una build nativa ora viene rifiutato.** I Mac con Apple silicon possono ancora eseguire le app Intel tramite traduzione, quindi un download solo Intel superava il controllo “funzionerà sul tuo Mac?” e si installava senza problemi, lasciandoti con una copia tradotta di un’app che prima girava in modo nativo, senza avvisi e con ogni aggiornamento futuro che avrebbe fatto di nuovo lo stesso. Ora ogni installazione sul posto confronta ciò che hai con ciò che è arrivato e rifiuta quella sostituzione. Il passaggio inverso, o da una build universale a una per Apple silicon, è normale ed è ancora consentito.

**Quando non riesce a dimostrare per quale architettura è un download, ora rinuncia invece di tirare a indovinare.** Alcuni produttori pubblicano una build per Apple silicon accanto a quella predefinita, e l’unico modo per capire che quella predefinita è la build Intel è accorgersi che esiste l’altra. Se questa seconda verifica non va a buon fine (il server del produttore la rifiuta, la connessione cade o le due build non concordano sulla versione), DuoUpdater non considera più quel silenzio una risposta. Ti indica la versione e non propone l’installazione, che è l’esito onesto.

**Una regola non funzionante non può più sparire da Diagnostica.** Per le app coperte sia da una regola scritta a mano sia dal nuovo lettore di manifest (cioè la maggior parte, di proposito), il fallimento della regola veniva annullato dal successo del lettore subito dopo, quindi un’app la cui regola si era davvero rotta continuava a risultare in buono stato. Ora i due risultati vengono registrati separatamente. Inoltre il lettore di manifest segnala per la prima volta i propri errori: tre app sul Mac di sviluppo risultavano puntare a indirizzi che da tempo rispondevano “non trovato”, cosa che prima nulla avrebbe detto apertamente.

**Le righe che vedono un aggiornamento ma non possono installarlo ora propongono la stessa cosa in entrambi i posti.** La barra dei menu mostrava un pulsante “Apri” che apriva il Finder, e la finestra non mostrava nulla per la stessa riga.

## 0.3.75

**Le app basate su Electron ora vengono riconosciute senza che qualcuno debba prima registrarle.** Moltissime app per Mac contengono un piccolo file che indica dove si trovano i loro aggiornamenti. Finora DuoUpdater conosceva solo quelle per cui qualcuno aveva scritto a mano una regola: tutte le altre restavano nell’elenco senza versione accanto e senza modo di avvisarti dell’uscita di una nuova build. Ora legge direttamente quel file, come ha sempre fatto con quello di Sparkle, così un’app del genere è coperta dal giorno in cui la installi, non dal giorno in cui qualcuno se ne occupa.

**Le app che avevano già una regola scritta a mano restano invariate.** Il nuovo lettore viene dopo di esse, quindi può solo colmare una lacuna, mai sostituirsi a qualcosa che già funzionava.

**Due dettagli decidono se il download proposto è quello giusto, ed entrambi sono stati definiti verificando app reali invece di fare supposizioni.** Alcuni produttori indicano una build Intel come download “principale” pur pubblicandone accanto una per Apple silicon; altri danno alla build per Apple silicon un nome file identico nell’aspetto a quello della build Intel, quindi il nome non rivela nulla. DuoUpdater sceglie in base all’architettura e, quando non può essere sicuro che un download funzionerà sul tuo Mac, ti indica la versione e non propone l’installazione, invece di darti qualcosa che si installa senza problemi e poi non si apre.

## 0.3.74

**Se usi una build beta, release candidate o nightly di un’app, DuoUpdater seguiva in silenzio la linea sbagliata.** Capisce su quale linea sei cercando la tua build nell’elenco delle release del produttore, ma quando una pre-release mantiene lo stesso numero di versione pubblico della release stabile da cui deriva (che è la norma per una pre-release), finiva per abbinarla alla voce stabile. L’effetto era silenzioso: sullo schermo non compariva mai nulla di sbagliato, semplicemente non venivi mai a sapere della build successiva sulla tua linea, e le note di rilascio che vedevi appartenevano alla linea stabile. Il problema è emerso installando le vere build di pre-release di Supacode e TypeWhisper e osservando cosa succedeva; ora entrambe seguono la linea su cui si trovano davvero.

**La beta di CapCut mostrava una versione che non hai.** La riga diceva “9.3.4545 → 9.4.0-beta6”, mentre CapCut stesso, il Finder e ogni altro programma di aggiornamento indicavano la tua copia come 9.4.0-beta5. Alcune app mettono la versione reale in un campo diverso da quello usato dalla maggior parte, e DuoUpdater leggeva quello dall’aspetto più ordinato dal tuo lato della freccia e quello reale dal lato del produttore. L’aggiornamento proposto era sempre quello giusto: sbagliata era solo l’etichetta. Ora entrambe le metà della riga provengono dalla stessa fonte, per CapCut e per le altre sette app fatte allo stesso modo.

**MacWhisper, GitHub Copilot for Xcode, TypeWhisper e OpenUsage ora mostrano le loro note di rilascio.** Tutte e quattro avevano il pannello delle note vuoto: i loro feed di aggiornamento non contengono alcuna nota, e nessuno se n’era accorto finché ognuna non è stata confrontata con ciò che il produttore pubblica davvero. Ora DuoUpdater legge la pagina delle note di rilascio di MacWhisper, il file changelog di Copilot e il sito del changelog di TypeWhisper, e rimanda OpenUsage al suo elenco di release.

**Helium ora si aggiorna tramite il proprio servizio di aggiornamento, che porta con sé il canale beta e download molto più piccoli.** Veniva seguito tramite il suo elenco pubblico di release, che mostra solo le build stabili, quindi a chi usava la beta di Helium veniva proposta quella stabile. Il suo servizio pubblica anche patch, così un normale aggiornamento pesa circa 40 MB invece di dover riscaricare 124 MB. Verificato sia con una build stabile sia con una beta, e il download viene controllato con la chiave di firma contenuta nella tua copia installata prima di sostituire qualsiasi cosa.

## 0.3.73

**Le release beta, developer e nightly di Firefox e Thunderbird ora vengono seguite correttamente: fino a oggi nessuna di queste cinque linee aveva mai segnalato un solo aggiornamento.** Venivano lette dal file di versione pubblico di Mozilla, che pubblica solo la versione che ti viene mostrata, e installando una beta la “b5” viene tolta: una beta di Firefox si presenta come 155.0 per tutto il ciclo, quindi l’unica domanda che veniva posta era “155.0b5 è più recente di 155.0?”, e la risposta è no. Con Nightly andava peggio: Mozilla ne pubblica una ogni giorno e si chiamano tutte 157.0a1, quindi un ciclo di quattro settimane non produceva assolutamente nulla. Ora DuoUpdater interroga il servizio di aggiornamento di Mozilla, lo stesso indirizzo usato dal programma di aggiornamento integrato di Firefox e indicato all’interno dell’app, e confronta l’identificativo di build presente da entrambe le parti. Prima del rilascio è stato verificato con i download reali di tutte e cinque le linee: l’identificativo riportato da quel servizio coincide byte per byte con quello contenuto nell’app che hai; una beta indietro di una build ora mostra il suo aggiornamento, e lo stesso vale per una nightly compilata prima nello stesso giorno. Le release stabili ed ESR non sono mai state interessate e restano invariate. Un limite va detto chiaramente: quel servizio non pubblica alcuna data di rilascio, quindi per queste cinque linee il Registro release continua a indicare quando DuoUpdater ha visto per la prima volta una build, non quando Mozilla l’ha pubblicata.

## 0.3.72

**Wispr Flow, AionUi e Devin ora si aggiornano con un clic, invece di limitarsi a dirti che esiste una nuova versione.** Tutte e tre vedevano già i propri aggiornamenti, ma nessuna poteva applicarli, per un motivo dichiarato: il produttore distribuisce build separate per Intel e per Apple silicon e DuoUpdater non aveva modo di scegliere. Verificato sul campo anziché dato per scontato, quel motivo non reggeva: gli endpoint da cui si leggono queste tre app sono già quelli per Apple silicon, e DuoUpdater funziona solo su Apple silicon, quindi non c’è mai stata una scelta da fare. Ogni download è stato scaricato e controllato prima di essere collegato: dentro c’è l’app giusta, firmata dallo stesso sviluppatore della copia che hai, autenticata da Apple, e quello di AionUi è stato verificato con il checksum pubblicato nel suo stesso manifest. Poi ciascuna è stata installata davvero, sopra una copia più vecchia, ed è ripartita con la nuova versione.

**Grok Bot ora è monitorata: nuove versioni e aggiornamenti con un clic.** L’app desktop di xAI è compilata e firmata da Anysphere, l’azienda dietro Cursor, e si aggiorna tramite il servizio di rilascio di Cursor: per questo nessuna delle strade abituali dava risposta. Niente feed Sparkle, nessuna scheda sull’App Store, nessun repository pubblico delle release, e un cask Homebrew che rimanda l’aggiornamento all’app stessa. DuoUpdater legge invece l’endpoint di versione del produttore. C’erano altri due endpoint, e sono stati scartati entrambi per motivi precisi: quello dietro il pulsante di download su x.ai non pubblica alcun numero di versione, e quello usato dal programma di aggiornamento dell’app risponde con un corpo vuoto quando sei già aggiornato, un silenzio impossibile da distinguere da un endpoint guasto. L’installazione è stata controllata prima di essere collegata: l’immagine disco contiene l’app vera, firmata dallo stesso sviluppatore della copia che hai e autenticata da Apple. Una cosa che volutamente non offre sono le note di rilascio: xAI non ne pubblica per questa app, e l’unico changelog che pubblica riguarda un altro prodotto.

**Anche Comet e Msty Studio si aggiornano con un clic, e ora un controllo segnala le app che potrebbero farlo ma non lo fanno.** Erano le ultime due del gruppo che vedevano gli aggiornamenti senza poterli applicare, ed è venuto fuori che non serviva niente di nuovo: bastava guardare meglio cosa invia davvero il produttore. Il link di download di Comet è firmato e scade dopo un’ora, quindi il pulsante di aggiornamento punta al gateway di Perplexity e il link viene generato nel momento in cui fai clic, non ore prima, quando è stato eseguito il controllo. Msty pubblica quattro download in un unico file, con quello per Intel al primo posto, e l’impronta usata per verificare il download veniva presa proprio da quella prima voce; ora è legata alla build per Apple silicon che viene effettivamente scaricata, e così di solito si accorge anche di una release uscita tra il controllo e il clic, invece di installarla in silenzio. Entrambe sono state scaricate e fatte passare per i veri controlli di installazione prima del rilascio. La lezione più generale non riguardava nessuna delle due: in DuoUpdater non c’era niente in grado di accorgersi di un’app lasciata in sola rilevazione per un motivo che non era più vero, quindi la scansione notturna delle ricette ora segnala quando un’app che si limita a monitorare ci sta già fornendo un programma di installazione.

**QQ音乐 ora è monitorata: nuove versioni, aggiornamenti con un clic e note di rilascio nella finestra.** Nessuna delle strade abituali dava risposta. Non ha un feed Sparkle né il framework Sparkle; il suo cask Homebrew rimanda l’aggiornamento all’app stessa; e l’endpoint di aggiornamento indicato dal suo stesso eseguibile risponde 200 con un corpo vuoto a qualsiasi richiesta possiamo fargli, un silenzio impossibile da distinguere da un endpoint guasto, perciò è stato lasciato perdere. DuoUpdater legge invece il file di dati da cui è costruita la pagina di download del produttore: quella pagina arriva come un guscio vuoto e si riempie a partire da quel file, che è anche l’unico posto in cui esistono le note di rilascio. Non c’è un blog, né un appcast, né una pagina per ogni versione. Le note vengono quindi lette direttamente da lì e mostrate nella finestra di DuoUpdater, e l’aggiornamento installa l’immagine disco autenticata indicata nella stessa risposta. Una trappola da annotare: quel file contiene ancora, accanto a quello attuale, un secondo record Mac vecchio di sei anni, quindi entrambe le regole si basano sul nome del file con la versione del download per Mac e non sulla parola “Mac”. E un limite da dire chiaramente: il file pubblica la versione che vedi ma mai il numero di build sottostante, quindi una nuova compilazione che mantiene lo stesso nome di versione qui è invisibile. Non può inventarsi un aggiornamento che non c’è: semplicemente non vede quel tipo di aggiornamento.

**TimeMachineEditor ora è monitorata: nuove versioni e aggiornamenti con un clic.** Nessuna delle strade abituali dava risposta: niente feed Sparkle (l’app non contiene né l’indirizzo di un feed né il framework che lo userebbe), nessuna scheda sull’App Store, nessun repository pubblico delle release, e un cask Homebrew che rimanda l’aggiornamento all’app stessa. Quello che ha è un piccolo sito del produttore il cui unico link di download riporta la versione nel testo stesso: è la stessa pagina, letta nello stesso modo, su cui si basa il controllo di versione di Homebrew, quindi è la fonte prevista dal produttore e non un’ipotesi. L’aggiornamento si installa tramite il pacchetto di installazione del produttore e non come semplice sostituzione dell’app, ed è una scelta voluta: il download installa anche, fuori dall’app, uno scheduler in background, uno strumento da riga di comando e un launch daemon, quindi sostituire solo l’app lascerebbe una copia nuova accanto a uno scheduler vecchio, senza che niente si accorga della discrepanza.

**Little Snitch ora è monitorata, sia nelle release stabili sia in quelle nightly.** Object Development pubblica un file di versione a cui ricorre il suo stesso programma di aggiornamento, lo stesso che legge Homebrew, e DuoUpdater lo legge direttamente, perché Little Snitch non ha un feed Sparkle e il suo cask rimanda l’aggiornamento all’app. Le due release condividono la stessa identità, cosa che normalmente le rende impossibili da distinguere; qui però la stringa di versione le tradisce: una build nightly scrive la parola per intero (“6.5 nightly (7301)”), mentre quella stabile si presenta come un semplice “6.4.1”. Vale la pena dire cosa volutamente non fa: non installa l’aggiornamento al posto tuo. Little Snitch fa girare un’estensione di sistema e un servizio in background privilegiato insieme all’app, e non è stato verificato su una macchina reale se sostituire solo l’app li lasci intatti; perciò DuoUpdater ti avvisa che la nuova versione è uscita e ti manda al download del produttore, invece di andare a tentativi con un filtro di rete.

**Carbon Copy Cloner ora è monitorata, e non proverà a farti passare da una versione principale all’altra.** Bombich mantiene vive tre generazioni contemporaneamente, CCC 5, 6 e 7, che si presentano tutte al sistema con la stessa identità, e questo rende la domanda “c’è qualcosa di più recente?” più insidiosa di quanto sembri: 7.1.6 è davvero una versione successiva a 6.1.13, ma passare dall’una all’altra è un acquisto separato, e CCC 7 richiede una versione di macOS più recente di quella che un Mac con CCC 5 potrebbe avere. Rispondere solo in base al numero di versione avrebbe detto a ogni utente di CCC 5 e 6 che lo aspettava un aggiornamento gratuito, per sempre, e sarebbe stato sbagliato ogni volta. Quindi DuoUpdater legge ogni generazione dal suo indirizzo e offre solo la release successiva all’interno della generazione che hai davvero. Vengono rilevate anche le beta, per chi le ha attivate in CCC. Per ora solo rilevazione, perché CCC installa un helper privilegiato accanto all’app, un passo più impegnativo rispetto agli aggiornamenti con un clic già presenti. Vale la pena annotare anche perché finora nessuno vedesse questi aggiornamenti: il feed di aggiornamento dell’app risponde con successo a ogni richiesta, con una pagina completamente vuota.

**Un aggiornamento che il tuo Mac non può eseguire non viene più scaricato né installato.** Ogni bundle di app indica la versione di macOS più vecchia su cui si avvia, e alcuni produttori indicano anche la più recente (“questa build non è per un sistema così nuovo”), che è il modo in cui un’app non ancora pronta per macOS 27 lo segnala. DuoUpdater non leggeva né l’una né l’altra. Per le app monitorate tramite un feed Sparkle il limite minimo era già rispettato, ma sono una minoranza: tra le app di un Mac tipico, quelle lette dall’endpoint di un produttore o dalle release di GitHub sono la metà più grande, e una release di GitHub non pubblica da nessuna parte un requisito di macOS. Così un’app passata a un macOS più recente del tuo poteva esserti offerta, scaricata per intero, sostituita e poi non aprirsi. Ora DuoUpdater legge il requisito dall’app scaricata, subito accanto al controllo già esistente che sia compilata per il tuo processore, e rifiuta la sostituzione invece di rimpiazzare una copia funzionante con una che non si avvierà. Viene rispettato anche il limite massimo indicato dal produttore, quando un feed lo pubblica, quindi una build che lo sviluppatore ha segnato come non adatta al tuo macOS non viene proprio offerta. Tre limiti da dire chiaramente. Leggere il requisito dal download significa che il download è già avvenuto: questo evita un’installazione rotta, non il traffico, perché per la maggior parte delle app non c’è un punto precedente in cui chiederlo. Un’app la cui versione più recente non può girare sul tuo Mac continuerà a mostrare quell’aggiornamento e a rifiutarsi di installarlo; ora il rifiuto indica quale versione di macOS serve, ma DuoUpdater non si ricorda ancora la risposta per smettere di offrirlo. E il controllo copre le strade in cui è DuoUpdater stesso a sostituire il bundle dell’app: un pacchetto di installazione passa il file a macOS, che applica i requisiti del pacchetto, mentre Homebrew e l’App Store scelgono da sé le proprie build; le app arrivate dalla sezione iPhone e iPad dell’App Store vengono saltate di proposito, perché la versione che indicano è di iOS e confrontarla con macOS sarebbe peggio che non controllare. Una cosa che non dice ancora esplicitamente: quando uno sviluppatore ha segnato una build come non adatta al tuo macOS, quell’aggiornamento semplicemente non viene offerto e l’app risulta aggiornata, senza spiegare perché. Su un Mac più vecchio la cosa si risolve il giorno in cui aggiorni macOS. Su un Mac troppo nuovo no, e lì serve una risposta migliore del silenzio.

## 0.3.71


**百度网盘 ora è monitorata: nuove versioni, aggiornamenti con un clic e note di rilascio nella finestra.** Nessuna delle strade abituali era percorribile. Non pubblica un feed Sparkle; il cask Homebrew non può rispondere per una copia installata a mano; e il manifest di aggiornamento indicato nel suo stesso bundle è morto: quel file, il suo gemello arm64 e la cartella che li contiene rispondono tutti 404. Quindi DuoUpdater legge l’endpoint da cui è costruita la pagina di download del produttore e installa l’immagine disco arm64 autenticata indicata nella stessa risposta. Le note di rilascio arrivano allo stesso modo: la pagina “版本更新” ha una scheda Mac版, ma la pagina arriva vuota e si riempie tramite un’API, quindi DuoUpdater legge direttamente quell’API e mostra le ultime quaranta release nella propria finestra. Un limite da dire chiaramente: quel feed pubblica la versione che vedi ma mai il numero di build sottostante, quindi una nuova compilazione che mantiene lo stesso nome di versione qui è invisibile. Non può inventarsi un aggiornamento che non c’è: semplicemente non vede quel tipo di aggiornamento.

**Un controllo non riuscito ora dice di non essere riuscito, invece di mostrare uno spazio vuoto.** Un’app la cui versione può essere indicata solo dall’endpoint del produttore aveva un unico modo per dire “nessuna risposta”: un trattino, che è anche l’aspetto di un’app non coperta da niente. Così un endpoint del produttore che andava in timeout, o che cambiava indirizzo, sembrava esattamente un “DuoUpdater non monitora questa app”: un verdetto dall’aria definitiva, senza il pulsante Riprova e senza comparire nel conteggio “Impossibile controllare N app”. Ora risultano come un controllo non riuscito, che è quello che sono: con un pulsante Riprova, un posto nel conteggio e il motivo indicato. Non vale per tutto, di proposito: una condizione su cui il tuo Mac non può fare nulla (nessuna ricetta per il canale di rilascio che segui, un endpoint che richiede un’identità che questa macchina non ha) resta il trattino discreto di sempre, e un controllo fallito per tre giri di fila esce comunque dal banner invece di restarci fisso per sempre. Un’app installata da JetBrains Toolbox mantiene anche il pulsante “apri Toolbox” quando la lettura della versione che c’è dietro fallisce, perché aprire Toolbox era la risposta in ogni caso.

**Il promemoria “riapri per applicarlo” ora sparisce una volta che hai riaperto l’app.** Quando il programma di aggiornamento di un’app scaricava una build in background, DuoUpdater te lo diceva e offriva un pulsante Riapri nella notifica. Usarlo funzionava: l’app ripartiva con la nuova build e diceva “Ora in esecuzione: 1.0”. Ma il promemoria che sostituiva restava sotto, nel Centro Notifiche, a chiederti ancora di riaprire qualcosa che avevi appena riaperto. DuoUpdater aspettava che il promemoria *smettesse* di essere pertinente, e il momento in cui controllava era proprio l’unico già messo in conto. Ora rimuove il promemoria ogni volta che non ci sono riaperture in sospeso, e così elimina anche quello lasciato da un’app che ha applicato il proprio aggiornamento mentre DuoUpdater non era in esecuzione.

## 0.3.70

**Le app che distribuiscono molte build con lo stesso numero di versione ora vengono gestite correttamente, ovunque.** Un’app per Mac ha due stringhe di versione: quella che ti mostra (“1.0”) e un numero di build che è quello che cresce davvero. La maggior parte delle app le aggiorna entrambe. Alcune aggiornano solo la build: Amp ha rilasciato dieci build in un solo giorno, tutte chiamate 1.0; Surge ha rilasciato quattro versioni distinte come 6.9.0; le build di anteprima di JetBrains fanno lo stesso. DuoUpdater decideva se “è cambiato qualcosa?” confrontando la versione *mostrata* in una dozzina di punti, e per quelle app il confronto poteva rispondere solo “no” (oppure, dove chiedeva “sono uguali?”, “sì”), qualunque cosa fosse successa davvero. Ecco cosa ha rotto. È un unico errore, scoperto perché Amp l’ha reso visibile.

**Riapri non sembra più bloccarsi per tre minuti per poi segnalare un errore mai avvenuto.** Facendo clic su Riapri per un’app il cui programma di aggiornamento aveva una build in attesa, la rotellina girava per tre minuti e poi diceva che l’operazione non era riuscita, mentre in realtà l’aggiornamento era stato applicato in un secondo o due e l’app si era già riaperta con la nuova build. DuoUpdater aspettava un cambiamento della versione mostrata che non sarebbe mai arrivato. Misurato su Amp: 189 secondi di rotellina per una sostituzione durata meno di uno. Ora si conclude in molto meno di un secondo, e un errore reale viene ancora segnalato come tale.

**Riapri non ti offre più una build già superata.** Quando il programma di aggiornamento di un’app aveva scaricato una build e nel frattempo lo sviluppatore ne aveva pubblicata un’altra, DuoUpdater offriva comunque Riapri: così riaprivi e ti ritrovavi subito indietro di una build, che è esattamente ciò che quel controllo doveva evitare. Ora quelle righe offrono invece **Aggiorna**, che scarica la build attuale.

**Saltare una versione non zittisce più un’app per sempre.** Questa è quella che conviene conoscere. “Salta questa versione” serve a rifiutare una release e lasciar passare la successiva. Registrava però solo la versione mostrata, quindi per un’app che mantiene lo stesso nome di versione tra una build e l’altra, saltare una volta significava rifiutare *tutte* le release future: per sempre, anche dopo un riavvio, senza niente sullo schermo a indicare che l’app era stata messa a tacere. Ora un salto registra la build rifiutata. Una conseguenza della correzione: una versione saltata con un DuoUpdater precedente ti verrà offerta ancora una volta, perché il vecchio record non può dire a quale build si riferiva. Se la salti di nuovo, verrà registrata correttamente.

**Il ripristino torna disponibile per gli aggiornamenti che sembravano non aver cambiato nulla.** Il banco di lavoro nasconde un ripristino che non avrebbe alcun effetto, e per queste app ogni ripristino sembrava non avere effetto, quindi la riga spariva dopo un aggiornamento vero mentre sul disco c’era un backup completo impossibile da raggiungere.

**Il promemoria per riaprire torna ad apparire una volta per ogni build, e sopravvive anche se lo sviluppatore ne pubblica un’altra.** La 0.3.69 aveva sostituito un promemoria che si ripeteva ogni cinque minuti con uno che compare una sola volta per ogni build in attesa, ma identificava la build dal nome, quindi per queste app annunciava la prima e poi taceva per tutte le successive. Ora è corretto. Inoltre: se un’app si rifiuta di chiudersi perché ha modifiche non salvate, DuoUpdater prende nota di riaprirla dopo che hai risposto. Quella nota veniva scartata se lo sviluppatore pubblicava un’altra build mentre stavi decidendo, e dopo la sostituzione l’app restava chiusa senza che niente la riaprisse. Ora la nota segue la nuova build.

**Un aggiornamento dall’App Store non riuscito non viene più registrato in silenzio come riuscito**, e un pacchetto di installazione scaricato non viene più scambiato per quello attualmente disponibile quando si tratta di una build più vecchia. Entrambi i problemi venivano dallo stesso confronto. Anche la cronologia delle release contava dieci build di un’app come un’unica release; d’ora in poi le conta separatamente, anche se la cronologia già registrata non può essere recuperata.

**La riga stessa indica quale build verrà applicata riaprendo l’app.** Prima diceva “1.0 → 1.0”, una riga che non indicava alcuna differenza. Ora dice “1.0 (129) → 1.0 (130)”, e solo quando a cambiare è la build; se i nomi delle versioni sono già diversi, la riga resta com’era. La stessa correzione arriva ai suggerimenti di Riapri, alla notifica, alla nota che spiega perché un’installazione è stata rimandata e al messaggio di rifiuto di `duo install`.

## 0.3.69

**微信输入法 e 豆包输入法 si possono di nuovo aggiornare con un clic, e vengono aggiornati nello stesso modo in cui si aggiornano da soli.** L’aggiornamento con un clic per i metodi di input era stato ritirato nella 0.3.25 il giorno stesso dell’uscita, dopo che a qualcuno erano sparite le impostazioni del metodo di input. Il problema stava nella forma dell’installazione: sostituiva l’intera app, come fa un programma di installazione alla prima installazione. Un metodo di input è registrato in macOS in base alla *posizione* della sua app, ed entrambe queste app si aggiornano senza toccare quella posizione: mantengono l’app e ne scambiano il contenuto. Ora DuoUpdater fa lo stesso, quindi l’app registrata esce da un aggiornamento come la stessa app, e un errore in qualsiasi momento lascia la copia che stavi usando esattamente dov’era. Inoltre nessuna delle due ti chiede più la password.

**Prima di aggiornarli, tutto quello che hanno imparato viene copiato.** Il tuo dizionario, le tue impostazioni e lo stato del tuo account non stanno dentro l’app, quindi la copia di ripristino che DuoUpdater già conservava non poteva includerli. Ora ne viene fatta un’istantanea prima di ogni aggiornamento di un metodo di input, e vengono rimessi al loro posto con il ripristino; la copia non costa quasi nulla: i 578 MB di uno dei due richiedono un decimo di secondo e quasi niente spazio su disco. È una rete di sicurezza, non una riparazione: quello che un’app decide di fare con i tuoi dati al suo avvio successivo è codice dell’app stessa, e niente può frapporsi. Adesso però c’è qualcosa a cui tornare.

**Un aggiornamento non toglie più di nascosto a un’app la capacità di aggiornarsi da sola.** Quando DuoUpdater aveva bisogno di un amministratore per sostituire un’app, ripristinava il proprietario dell’app ma non i permessi con cui era stata installata, e un download di solito si estrae con permessi più ristretti di quelli impostati da un programma di installazione. Per entrambi i metodi di input, questa è la differenza tra un programma di aggiornamento che riesce a completare l’aggiornamento successivo e uno che non riesce a fare pulizia dopo di sé. Ora i permessi con cui un’app era stata installata vengono trasferiti sulla copia che la sostituisce.

**DuoUpdater smette di chiederti di riaprire la stessa app ogni cinque minuti.** Un’app che si aggiorna da sola mette la nuova versione da parte sul disco e aspetta che tu la chiuda. DuoUpdater se ne accorgeva a ogni controllo e pubblicava un promemoria ogni volta, quindi una build che avevi deciso di non riaprire ancora continuava a tormentarti per tutto il tempo in cui la lasciavi lì. Ora ogni build viene annunciata una volta sola: se la riapri, la salti o ignori l’app, non si fa più sentire, e la build successiva si annuncia normalmente.

**Un’app in attesa di essere riaperta conta come aggiornamento, e una ignorata non conta più affatto.** Una nuova versione già presente sul disco *è* un aggiornamento, solo scaricato in anticipo, quindi ora viene contata nel badge e nella riga “N aggiornamenti disponibili” invece che in un conteggio separato lì accanto. Le app ignorate andavano nella direzione opposta: un’app che avevi ignorato poteva accendere il badge mentre la sua riga mostrava un’etichetta attenuata “Ignorata” e nessun pulsante da premere, quindi il numero indicava qualcosa su cui non potevi agire. Ora ignorare e saltare significano la stessa cosa in tutti e tre i punti: il promemoria, il badge e l’elenco.

**搜狗输入法 ora è monitorata, interrogando il suo stesso programma di aggiornamento invece di leggere il sito web.** La pagina del changelog di Sogou pubblica numeri di versione a tre segmenti, mentre la copia installata ne ha quattro, quindi confrontarli avrebbe richiesto di tagliare prima la versione reale. Il controllo di aggiornamento dell’app, invece, risponde con la stessa numerazione del bundle. DuoUpdater interroga quell’endpoint come fa l’app e ne legge la release con tutti e quattro i segmenti, quindi è visibile anche una nuova compilazione che cambia solo l’ultimo. Questa è solo rilevazione: il programma di aggiornamento di Sogou fa molto più che scambiare l’app (registra di nuovo un generatore QuickLook, sposta i tuoi dati in una nuova posizione e chiude forzatamente il metodo di input), quindi l’aggiornamento vero e proprio è lasciato a lui. Una cosa da sapere, e dipende da Sogou, non da noi: il loro endpoint risponde in base alla versione di macOS che fa la richiesta, e un Mac con macOS 28 che chiede per sé riceve una build del 2023. DuoUpdater non chiede per sé, quindi la versione che vedi è quella attuale su ogni Mac.

**Le note di rilascio che una correzione successiva avrebbe letto correttamente vengono rilette, invece di restare sbagliate per sempre.** Le note vengono memorizzate nella cache per versione, partendo dall’idea che le note di una versione già rilasciata non cambiano mai. Questo vale per le note, non per quello che DuoUpdater riesce a estrarne, quindi un’app le cui note uscivano confuse restava così per quella versione, per quante correzioni all’analisi arrivassero dopo. Ora ogni voce in cache registra quale generazione della logica di estrazione l’ha scritta, e quelle scritte da una generazione più vecchia vengono scaricate di nuovo. Lo fanno entrambe le cache: i changelog delle app e le note delle formule Homebrew.

**Un controllo che fallisce sulla CDN di qualcun altro viene ripetuto una volta prima di essere considerato guasto.** 502, 503 e 504 significano tutti che un intermediario non è riuscito a raggiungere il server che sta dietro: la richiesta non è mai arrivata, quindi di solito la stessa richiesta funziona un attimo dopo. Il controllo di Headlamp falliva proprio così: GitHub rispondeva 504 senza nemmeno un’intestazione di limite di richieste. Ora questi tre codici ottengono un nuovo tentativo, dopo otto decimi di secondo. Di proposito solo questi tre: un 500 è un errore del server stesso e ripeterlo per lo più lo riproduce, e ritentare quando si è superato un limite di richieste consuma proprio il margine di cui ci si sta lamentando.

**Le note di rilascio di una formula Homebrew seguono la versione a cui appartengono.** Le note venivano memorizzate per formula e mai per versione, quindi, una volta caricate le note di una formula, per il resto della sessione ogni volta che la aprivi ricevevi le note di quella prima versione, anche dopo l’uscita di una versione più recente. Inoltre la loro lettura occupava la coda da cui dipendeva il resto dell’elenco delle formule, quindi un `brew info` lento poteva bloccare l’elenco intorno.

**Fai clic destro su un’app nella barra laterale del banco di lavoro per aprirla.** È lo stesso comando Apri che le righe della barra dei menu hanno sempre offerto, nella finestra in cui è più probabile che ti serva.

**Scartando un programma di installazione scaricato si elimina anche l’errore che aveva lasciato.** Buttare via un pacchetto pronto riportava già la riga su Aggiorna, ma un errore in rosso del tentativo che avevi appena annullato restava lì, e niente lo avrebbe mai tolto, perché un errore viene rimosso solo quando la riga risulta aggiornata, cosa che non succede mai a una riga che offre ancora un aggiornamento. Ora se ne va insieme al download.

**`duo`, lo strumento opzionale da riga di comando, smette di descriversi in modo impreciso.** `--timeout` non c’è più: veniva accettato, era documentato e non lo leggeva niente. `--budget` è documentato per la prima volta, e l’unico messaggio che lo cita ora indica il numero reale di minuti invece di dire sempre “15”. `--max-calls` dichiarava un valore predefinito di 20, mentre è 6. Un’opzione numerica a cui si passa qualcosa che non è un numero ora dà errore: `duo verify --max-concurrency 1x` veniva ignorato e la scansione partiva con il valore predefinito di quattro, cioè il contrario di quello che vuole chi sta rallentando apposta una scansione. E `duo verify` conta le richieste che ha fatto davvero: un feed che risponde 502 e riesce al secondo tentativo non riporta più un `ok` pulito dopo aver chiesto due volte senza dirlo. `-h` funziona ovunque funzioni `--help`.

## 0.3.68

**Altre quattro app monitorate, altri due canali di rilascio, e tutti si aggiornano direttamente.** CapCut, Canva e WorkBuddy su entrambi i siti da cui viene distribuita: quello internazionale e quello cinese seguono cicli di rilascio indipendenti, quindi a un’installazione vengono offerte solo la versione e le note del suo sito. Termius e VSCodium aggiungono i canali Beta e Insiders accanto alle build stabili già coperte. Il secondo canale di CapCut è quello delicato: si sceglie con un interruttore dentro CapCut e non compare da nessuna parte nel numero di versione, quindi il canale che segui viene letto dalla copia sul disco invece di essere dedotto dalla build che stai usando in quel momento. Da sapere se attivi quell’opzione: DuoUpdater ti offrirà la beta più recente non appena esiste, anche prima che il rilascio graduale di CapCut arrivi a te.

**I canali di anteprima di Android Studio non ti offrono più una build più vecchia di quella che hai.** Google elenca le release in ordine di pubblicazione e non per versione, e DuoUpdater cercava in quell’elenco tre volte distinte (una per la versione, una per la data, una per il download), quindi una release candidate pubblicata dopo una canary più recente poteva fornire la versione da una voce e il file da un’altra. Il 26 agosto il canale Canary rispondeva con 2026.1.4 RC 2 mentre 2026.2.1 Canary 2 era già uscita. Ora ognuna di queste risposte deve provenire dalla stessa voce.

**Una release ricompilata non installa più la copia che doveva sostituire.** Quando un progetto ricompila una release senza cambiarne la versione, entrambi i file restano sotto lo stesso tag (KeePassXC distribuisce `KeePassXC-2.7.11-1-arm64.dmg` accanto all’originale `KeePassXC-2.7.11-arm64.dmg`), e DuoUpdater prendeva quello elencato per primo. L’ordine è alfabetico: questa volta metteva per prima la ricompilazione, la volta successiva l’avrebbe messa per ultima. Non se ne vedeva nulla: la versione sulla riga era corretta, solo il file dietro era sbagliato. Ora il file giusto viene scelto in base a ciò che dice il nome del file stesso.

**Le build nightly e snapshot vengono riconosciute come le build di pre-release che sono.** La nightly di VLC, la snapshot di KeePassXC e la nightly di Freelens si installano tutte con il nome e l’identificatore di bundle dell’app stabile, quindi solo la stringa di versione le tradisce, e non veniva letta. Contavano come installazioni stabili, ed è così che a una nightly finisce per essere offerta una release normale che la sovrascriva. La nightly di DB Browser for SQLite viene letta dal nome del file dell’app per lo stesso motivo, e lì il problema era reale ma nascosto: la sua versione bloccata risulta superiore a quella stabile attuale solo finché la stabile non la raggiunge, e a quel punto a ogni installazione nightly sarebbe stata consegnata in silenzio una build stabile.

**La riapertura di un’app riporta quello che è successo davvero.** Alcune app contengono una seconda app nel proprio bundle (Surge ci tiene la sua Dashboard) e, quando andava riavviata solo quell’app interna, DuoUpdater diceva che era stata riaperta l’app esterna, anche se non era successo niente. Ora riporta l’esito dell’app interna, e non mostra più una notifica di riapertura per una riapertura mai avvenuta.

**Un aggiornamento già scaricato lo dice, e si può annullare.** Una riga con un pacchetto di installazione già scaricato mostrava un pulsante blu Installa e nient’altro: niente diceva che il download era già completato, o che il pulsante riapre il programma di installazione invece di ricominciare l’aggiornamento, e non c’era modo di cambiare idea. Ora è indicato sulla riga stessa invece che nascosto in un suggerimento, e **Scarta programma di installazione scaricato** nel menu contestuale della riga butta via il download e riporta la riga su Aggiorna. Scartarne uno mentre era già in corso un’installazione della stessa app poteva anche buttare via un pacchetto appena scaricato; ora non può più succedere.

**I pulsanti delle note di rilascio che puntavano a pagine dismesse aprono di nuovo pagine attive.** Microsoft ha rinominato le pagine delle note di rilascio di Edge per le aziende e Termius ha spostato il suo changelog, quindi tre canali di Edge e Termius ti mandavano a una pagina che non esisteva più. Nessuno aveva mai controllato se quelle pagine ci fossero ancora, ed è per questo che potevano degradarsi all’infinito mentre tutto il resto sembrava a posto; ora vengono controllate periodicamente. Il canale Dev di Edge non ha più alcun pulsante: Microsoft ha smesso di pubblicarne le note, e tutte le pagine ancora esistenti appartengono a un altro ciclo di rilascio.

**Raycast viene seguita fino alla versione 2, e solo sui Mac che possono eseguirla.** Raycast 2 richiede macOS Tahoe e Apple silicon. Un Mac che non soddisfa i requisiti resta sulla linea della versione 1 e non riceve più avvisi per una release che non avrebbe mai potuto installare. Inoltre le due linee ora hanno ciascuna le proprie note di rilascio, quindi un’installazione della versione 1 mostra la cronologia della versione 1 e non quella della versione 2.

**Le note di rilascio vengono mostrate nella finestra di DuoUpdater per altre app.** BetterDisplay su tutti e tre i suoi canali, Shotbase e WorkBuddy su entrambi i siti. Le note di BetterDisplay non finiscono più con il markup grezzo del suo pulsante di download, e non ripetono più l’elenco dei collaboratori a ogni singola release.

**`duo`, lo strumento opzionale da riga di comando, rifiuta una riga di comando che non capisce.** Un’opzione scritta male veniva ignorata, e un’opzione ignorata equivale a una mai passata: così `duo verify --githubb` controllava in silenzio tutte le ricette invece di quella richiesta. Opzioni sconosciute, un’opzione senza il suo valore e argomenti di troppo ora sono errori che indicano cosa accetta davvero il comando, e `--help` funziona dopo qualsiasi comando.

## 0.3.67

**Le build di pre-release e interne di BetterDisplay ora vengono offerte a chi le ha chieste.** BetterDisplay tiene tutte e tre le sue linee di rilascio in un unico feed di aggiornamento e sceglie tra queste con due interruttori nelle proprie impostazioni. DuoUpdater poteva solo dedurre la tua linea dalla build che stavi usando, che non dice nulla di un interruttore attivato ma non ancora messo in pratica: così chi aveva entrambi gli interruttori attivi e usava una build stabile si sentiva dire di essere aggiornato, mentre il programma di aggiornamento di BetterDisplay gli offriva una versione avanti di quattro release. Ora la tua scelta reale viene letta da BetterDisplay, compreso il caso in cui attivare le build interne continua a farti ricevere anche le normali pre-release. Le build di anteprima solo per Apple silicon sono escluse di proposito, così a un Mac Intel non ne viene mai offerta una che non può eseguire.

**Cambiare due volte di seguito il canale di rilascio di un’app non lascia più la riga bloccata sulla risposta vecchia.** Quando sposti un interruttore di canale, DuoUpdater ricontrolla quell’app, e un secondo cambio mentre il primo controllo era ancora in corso veniva ignorato: la riga continuava a offrire una beta a chi aveva appena disattivato le beta, finché qualcosa di non correlato non faceva partire un altro controllo. Ora il cambio più recente prende il posto di quello precedente, e un controllo interrotto a metà segna le app che non ha raggiunto per il passaggio successivo, invece di registrarle come già gestite. Inoltre le righe entrano nello stato di controllo prima dopo un cambio, quindi c’è meno tempo in cui sullo schermo resta una risposta che il tuo interruttore ha già reso superata.

## 0.3.66

**Un’app contenuta in un’altra app ora viene chiusa e riaperta insieme a quella.** Alcune app contengono una seconda app completa nel proprio bundle: Surge ci tiene la sua Dashboard. macOS la considera un’app separata, quindi niente la chiudeva quando veniva applicato un aggiornamento all’app che la contiene: continuava a eseguire la versione appena sostituita, da una copia che non era più dove pensava di essere, e da lì non riusciva a comunicare con l’app a cui appartiene. Ora queste app vengono chiuse insieme all’app che le contiene e riaperte dopo, e torna in primo piano la finestra in cui stavi effettivamente lavorando. Vengono trattate così solo le app che avresti potuto aprire tu; i processi helper invisibili che un’app esegue per sé vengono lasciati stare.

**I punti di ripristino che avevano smesso di essere creati senza dirlo vengono di nuovo creati.** Un’app può bloccare uno dei propri file perché niente possa eliminarlo, e la copia conservata per il ripristino ereditava quel blocco: non poteva mai essere sostituita dalla successiva, e un solo tentativo interrotto poteva lasciare una copia che niente riusciva a eliminare. Da lì in poi ogni aggiornamento di quell’app procedeva senza possibilità di tornare indietro, e lo diceva con una riga che non dava alcun motivo. Sul Mac dello sviluppatore un’app era rimasta in quello stato per due giorni. Le copie conservate per il ripristino non ereditano più il blocco, l’app installata resta esattamente come l’ha configurata il suo sviluppatore, e una copia rimasta bloccata non può più impedire la creazione di quella che deve sostituirla.

**Un aggiornamento andato a buon fine non dice più di non essere riuscito.** macOS può mettere al suo posto una nuova versione e poi fallire nel rimuovere quella sostituita. Questo veniva preso alla lettera: DuoUpdater diceva che un’app non era stata aggiornata quando invece lo era, oppure che non c’era un punto di ripristino mentre ce n’era uno completo nell’archivio dei backup; e nel primo caso ti mandava a concedere un’autorizzazione che avevi già concesso e che comunque non sarebbe servito. Ora, prima di riportare qualsiasi cosa, viene verificato cosa è successo davvero sul disco.

**Le righe delle versioni non ripetono più cifre già contenute nel numero di versione.** Quando un’app è in attesa di essere riaperta, la riga mostra la versione che stai usando e quella a cui arriverai riaprendola. Entrambe riportavano un numero di build, utile a rendere leggibile la differenza quando uno sviluppatore rilascia più build con lo stesso nome di versione, e puro rumore quando le versioni sono già diverse. La riga di Chrome consumava tutta la larghezza scrivendo “151.0.7922.174 (7922.17…” e finiva lo spazio prima delle cifre che cambiavano davvero. Ora i numeri di build compaiono solo quando sono proprio loro a essere cambiati.

## 0.3.65

**Ora c’è un’unica parola per riaprire un’app e completarne l’aggiornamento.** Un’app il cui programma di aggiornamento aveva già messo al suo posto la nuova versione ti chiedeva di “riavviarla”; una che tiene da parte la nuova versione finché non la chiudi ti chiedeva di “riaprirla”. Quella differenza esisteva dietro le quinte, ma per te non ne faceva alcuna: stesso clic in entrambi i casi, e stesso risultato se non fai clic, perché l’aggiornamento viene applicato comunque la prossima volta che chiudi l’app. Ora ovunque c’è scritto Riapri, anche nelle notifiche, nei suggerimenti e nell’impostazione che lo fa al posto tuo, ed è anche la parola che Chrome, Claude e la maggior parte delle app che si aggiornano da sole ti mettono davanti. Solo l’inglese aveva due parole per questo; tedesco, giapponese, russo e cinese ne hanno sempre usata una, e spagnolo e francese passano alla formulazione che già usavano altrove.

## 0.3.64

**Un aggiornamento che richiede un amministratore ora lo chiede, invece di fallire e dare la colpa a un’autorizzazione.** Se una sostituzione richiedesse una password veniva deciso guardando la cartella in cui si trova un’app, invece dell’app stessa. Tutto ciò che macOS aveva installato come root (ogni app dell’App Store e ogni app installata da un pacchetto di installazione) superava quel test, prendeva la strada che non richiede password e non poteva in alcun modo arrivare in fondo: per rimuovere la vecchia versione serve l’accesso in scrittura alle cartelle al suo interno. macOS segnala quel rifiuto con lo stesso codice che usa quando l’autorizzazione Gestione app è negata, quindi l’errore arrivava come una richiesta di concedere Gestione app, che non avrebbe mai potuto aiutare, perché l’ostacolo era il proprietario dei file. Su un Mac normale erano coinvolte tutte le app dell’App Store e qualche altra ancora, e il problema colpiva gli account amministratore: gli account standard venivano già indirizzati correttamente. Ora questi aggiornamenti prendono la strada che funziona, e l’app mantiene il proprietario che aveva invece di diventare tua senza che tu lo sappia.

**Anche le app dell’App Store ora hanno un punto di ripristino, come tutte le altre.** I backup le saltavano, partendo dall’idea che lo store può sempre recuperare una build precedente. Non può: l’App Store offre solo la versione attuale di un’app, e così lo store era l’unica strada che applicava un aggiornamento senza alcun modo di annullarlo. Ora queste app vengono salvate in un backup prima di un aggiornamento come tutte le altre, e dato che la copia viene creata per clonazione, non occupa quasi spazio su disco finché l’aggiornamento non sostituisce davvero l’originale. Quando ne ripristini una, ti viene detta la cosa specifica dello store: l’aggiornamento ricompare subito nell’elenco Aggiornamenti, e viene riapplicato da solo se gli aggiornamenti automatici delle app sono attivi. E quando un aggiornamento dello store non sarebbe mai stato applicato (un’app per iPhone eseguita su un Mac, un titolo non venduto nel tuo paese), non viene più creato un punto di ripristino, quindi una riga non può più proporti di tornare alla versione che sta già usando.

**Longbridge Desktop ora è monitorata, su entrambe le sue linee di rilascio.** Stable e Preview hanno ciascuna il rilevamento della versione, l’installazione con un clic della build ufficiale per Apple silicon e le note di rilascio mostrate nella finestra di DuoUpdater, illustrazioni comprese.

**Le note di rilascio di WhatsApp ora compaiono mentre il controllo sull’App Store è ancora in corso.** La pagina dell’App Store mostrata in quella finestra era archiviata con un nome che la ricerca non poteva mai trovare, quindi il riquadro delle note restava vuoto invece di mostrarla.

**L’intestazione del menu contiene di più in meno spazio.** La versione di DuoUpdater ora compare accanto al suo nome, e facendoci clic si aprono le sue note di rilascio. “Aggiorna tutto” è passato su una riga a sé, dove un’etichetta tradotta ha spazio per essere letta per intero, e le azioni in basso sono icone. Il banner che annunciava l’aggiornamento di DuoUpdater stesso non c’è più: si accende invece la scintilla accanto alla versione, e resta accesa finché non hai letto cosa è cambiato. Una riga di stato troppo lunga per il menu ora termina con i puntini di sospensione invece di allargarlo.

**Le impostazioni non tagliano più le opzioni di aggiornamento che propongono.** I due menu che decidono come applicare un aggiornamento troncavano le proprie etichette in diverse lingue. Ora il testo è più corto, e va a capo su una seconda riga dove le parole ne hanno ancora bisogno.

**Novità indica quando è uscita ogni versione.** Ogni versione nella colonna laterale ora riporta la data di pubblicazione.

## 0.3.63

**Gli aggiornamenti specifici per architettura ora scelgono la build che questo Mac può eseguire davvero.** Alcune app pubblicano la stessa versione due volte nello stesso feed Sparkle, una per Apple silicon e una per Intel, e DuoUpdater risolveva il pareggio in base all’indirizzo di download che per caso veniva prima in ordine alfabetico. Ora legge il requisito hardware del feed e, dove il produttore lo lascia vuoto, l’architettura indicata nel nome del file. La build nativa vince sempre, e una build che questo Mac non può avviare non viene offerta. Le release di GitHub ricevono lo stesso trattamento, senza che una ricetta perfettamente sana venga dichiarata guasta solo perché il suo file più recente è per un’altra architettura.

**I controlli degli aggiornamenti di ChatGPT ora seguono il canale di distribuzione associato all’account.** OpenAI a volte tiene gli account business ed enterprise su una build desktop precedente, mentre una nuova arriva prima agli account consumer. DuoUpdater non includeva il piano dell’account in quel controllo, e così selezionava in silenzio per tutti il canale prudente: poteva dire che la copia installata era in qualche modo più avanti mentre ChatGPT stava già scaricando una build più recente, oppure offrire una build che il programma di aggiornamento dell’app avrebbe sostituito di nuovo. Ora invia l’etichetta del piano, presa dallo stato di accesso di ChatGPT/Codex, nella stessa richiesta di aggiornamento che fa l’app. Se l’etichetta non è disponibile, mantiene il comportamento prudente; le credenziali non vengono mai inserite nella richiesta né nella diagnostica.

**Una riapertura a cui macOS non risponde mai non può più bloccare tutti gli aggiornamenti successivi.** Launch Services a volte accetta una richiesta di riaprire un’app aggiornata e poi non risponde mai. La riga restava su “Riapertura…” per sempre, il pulsante Riavvia rimaneva disattivato e l’aggiornamento di DuoUpdater stesso restava in coda dietro. Ora un avvio che non ha risposto dopo un minuto viene considerato non riuscito, così la riga si sblocca e il resto del programma di aggiornamento continua a funzionare.

**Il Registro release resta popolato quando trascini velocemente la barra di scorrimento.** Il vecchio stack caricato su richiesta poteva essere superato da un salto lungo, lasciando per un attimo la finestra vuota mentre le righe venivano create intorno alla nuova posizione. Ora il registro usa un elenco a riciclo che può saltare direttamente alla destinazione. Anche il pulsante di ricarica mantiene le stesse dimensioni quando passa dalla freccia alla rotellina, quindi l’ultima riga non sobbalza più quando parte un controllo.

**Traffico di download ora segnala gli aggiornamenti che hanno usato una patch binaria.** I nuovi download registrano la strada effettivamente completata, non solo se era stata offerta una patch, e nella cronologia portano un badge Delta. Vengono riconosciuti anche i download di patch nettamente più piccoli della 0.3.62, anche se erano stati registrati prima che il registro del traffico avesse un campo per la strada seguita.

## 0.3.62

**Ora gli aggiornamenti scaricano solo ciò che è cambiato, quando lo sviluppatore li pubblica in questo modo.** Alcune app distribuiscono una piccola patch insieme a ogni release, sufficiente a trasformare la versione che hai in quella nuova senza scaricare di nuovo tutto. DuoUpdater le ignorava e scaricava ogni volta il pacchetto completo. Ora usa la patch quando ce n’è una che corrisponde esattamente alla build che hai. L’ultimo aggiornamento di ChatGPT ha pesato 1,9 MB invece di 605 MB; quello di Docker 87 MB invece di 582 MB. Il risultato è in ogni caso la stessa identica applicazione: stessa firma, stessi byte, verificati rispetto al download completo prima del rilascio. Quando nessuna patch corrisponde a quello che hai, o l’applicazione della patch non riesce, viene fatto il download completo come prima, quindi nessuna installazione può fallire per questo motivo.

**DuoUpdater non scarica più un aggiornamento che un’app sta già scaricando da sola.** Molte app si aggiornano anche da sole, e se entrambi scaricavamo lo stesso file da 600 MB nello stesso momento, quel file lo pagavi due volte. Ora DuoUpdater si accorge di un download in corso e lo lascia stare, indicandolo sulla riga invece di non fare niente in silenzio. Se quel download risulta abbandonato, smette di tenerne conto dopo dieci minuti, così niente resta bloccato.

**Un aggiornamento che un’app ha già preparato non viene più sovrascritto.** Le app che si aggiornano da sole spesso scaricano in background e poi aspettano che tu le chiuda per mettere al suo posto la nuova versione. Installare sopra una di queste sembrava funzionare, ma si annullava nel momento in cui chiudevi l’app; e quando la versione in sospeso dell’app era più vecchia di quella appena installata da DuoUpdater, ti ritrovavi più indietro di prima. Ora questi aggiornamenti vengono lasciati completare, qualunque versione contengano.

**Anche gli aggiornamenti di DuoUpdater stesso sono più leggeri.** Le sue release ora includono lo stesso tipo di patch, quindi aggiornando da una versione recente si scaricano poche centinaia di kilobyte invece di undici megabyte.

## 0.3.61

**Le spiegazioni lasciate da un aggiornamento ora spariscono da sole.** Quando DuoUpdater passa un’app al suo programma di aggiornamento, la riga lo dice: “portata in primo piano perché il suo programma di aggiornamento applichi l’aggiornamento”. Quella frase restava lì per sempre: l’unica cosa che la toglieva era avviare un altro aggiornamento della stessa app, quindi rimaneva sotto la riga molto dopo che l’aggiornamento era stato applicato, a descrivere qualcosa finito ore prima. Ora sparisce non appena l’app è aggiornata. Un avviso che un aggiornamento è stato applicato senza punto di ripristino viene lasciato di proposito, perché descrive l’aggiornamento già avvenuto e comincia a contare solo quando è finito.

**Un aggiornamento rifiutato ora si spiega nella tua lingua.** Quando è già in corso un’altra installazione (DuoUpdater che lavora su un gruppo di app, o `duo` in un terminale), la riga te lo dice. Quel messaggio era solo in inglese, in una finestra per il resto tradotta, e terminava con il numero di un processo: utile in un terminale, inutilizzabile in un menu. Ora è tradotto e dice cosa fare invece di chi detiene il blocco. Lo strumento da riga di comando stampa ancora il numero del processo, dove puoi farci qualcosa.

**La riga sulle abitudini di rilascio, e il suo orario, ora seguono le tue impostazioni locali.** Registro release → Schemi riassumeva tutto con “Esce più spesso venerdì, verso le 18”. Le lingue che declinano i nomi dei giorni non possono dirlo inserendo il giorno a metà frase, e finivano con la forma sbagliata della parola: in russo si leggeva “Чаще всего выходит пятница” dove serve “по пятницам”. Ora è un’etichetta, “Picco: venerdì, verso le 18”, corretta in ogni lingua. L’orario segue la stessa logica: se il tuo Mac scrive gli orari nel formato a 24 ore, lo fa anche qui, compreso l’asse del grafico.

**La ricerca nelle impostazioni ora capisce le parole che vedi sullo schermo.** Il campo di ricerca sopra la barra laterale delle impostazioni cercava in un elenco di termini aggiuntivi scritto in inglese e mai tradotto, quindi “rollback” portava a Generali mentre “Zurücksetzen” e “回滚” non portavano da nessuna parte. Ora questi termini esistono in tutte le lingue di DuoUpdater. Quelli inglesi funzionano ancora in ogni lingua, perché la documentazione da cui provengono è in inglese.

## 0.3.60

**Attivare “Mostra tutto” non fa più esitare il menu.** L’elenco completo di tutte le tue app veniva misurato per intero ogni volta che compariva: su un Mac con 127 app era circa un secondo di lavoro, quasi tutto speso a disporre righe molto più in basso di quelle visibili. E lo si pagava a ogni attivazione, non solo la prima. Ora vengono costruite solo le righe effettivamente sullo schermo.

**Una spiegazione rimasta da un aggiornamento non riuscito non sopravvive più all’errore.** Quando un aggiornamento non poteva essere applicato (perché era già in corso un’altra installazione, per esempio) la riga ne spiegava il motivo, in rosso. Niente toglieva mai quella riga: anche quando l’aggiornamento andava a buon fine e la riga tornava a mostrare il segno di spunta, la vecchia spiegazione restava lì sotto, e ci rimaneva a ogni nuovo controllo finché DuoUpdater non veniva riavviato. Ora sparisce non appena l’app è aggiornata. I motivi relativi ad aggiornamenti ancora in attesa vengono lasciati, così uno che non hai ancora letto non può essere cancellato da un controllo in background.

**Il pulsante “Aggiorna tutto” non cambia più dimensione in base alla lunghezza dell’elenco.** Con pochi aggiornamenti in sospeso veniva disegnato più piccolo del dovuto, con ottanta punti di spazio vuoto accanto, e tornava alla dimensione corretta ogni volta che l’elenco si allungava. Ora mantiene sempre la dimensione prevista.

## 0.3.59

**Traffico di download ora indica a quale build è passato un aggiornamento, non solo a quale versione.** Molte app distribuiscono diverse build con lo stesso nome di versione (Surge ha pubblicato quattro release distinte come “6.9.0”), quindi quelle righe dicevano “6.9.0 → 6.9.0” e non ti dicevano niente. Ora dicono “6.9.0 (12028) → 6.9.0 (12030)”, e solo quando il nome della versione da solo non basta; quando la versione è già cambiata, il numero di build sarebbe solo rumore e viene omesso.

**La build registrata è quella effettivamente installata, letta dall’app stessa una volta completato l’aggiornamento.** Non il numero annunciato dal feed di aggiornamento dello sviluppatore: i feed a volte riportano dati sbagliati, e in questo modo funziona anche per le fonti che non pubblicano alcun numero di build: GitHub, Homebrew e l’App Store. Per un aggiornamento ancora in attesa nella finestra del programma di installazione di macOS non si tira mai a indovinare: non viene registrato niente finché non è reale.

**Un download che non ha cambiato nulla ora viene segnalato come tale.** A volte un aggiornamento scarica e installa la build che era già sul tuo Mac: un numero di versione sbagliato da parte dello sviluppatore, un mirror che serve quello che hai già. È banda consumata davvero senza alcun risultato, e la finestra del traffico è il posto in cui vorresti vederlo. Ora queste righe hanno l’etichetta “nessuna modifica”. I download registrati prima di questa release non hanno numeri di build da confrontare, quindi vengono lasciati stare invece di tirare a indovinare: sconosciuto non vuol dire invariato.

## 0.3.58

**DuoUpdater ora ti mostra quanto è costato davvero, in download, tenere aggiornate le tue app.** Contava già, byte per byte, ogni aggiornamento scaricato per te, ma il conteggio non compariva da nessuna parte, e il numero restava in un file che nessuno poteva leggere. Ora c’è una finestra Traffico di download, che si apre dal pulsante del grafico in fondo al menu, con il dato di questo mese scritto accanto al pulsante, così la domanda più frequente ha risposta senza aprire niente. All’interno: il totale, gli ultimi tre mesi affiancati con la variazione tra l’uno e l’altro, la ripartizione della provenienza dei byte e tutte le app in classifica in base a quanto sono costate. Fai clic su una per vedere ogni aggiornamento che ha ricevuto, da quale versione a quale è passata e quanto era grande quel download.

**Il totale è onesto su ciò che non può vedere.** Homebrew, l’App Store e le app che si aggiornano con il proprio programma di aggiornamento integrato scaricano i propri byte, e DuoUpdater non li gestisce mai: il dato quindi è un minimo, non un conteggio completo. È sempre stato così; la differenza è che ora la finestra lo dice in modo permanente, e non solo nella schermata vuota che vedi prima che sia stato registrato qualcosa.

**Le app che nel frattempo hai rinominato o eliminato mantengono la loro cronologia.** Il traffico viene registrato in base alla posizione dell’app sul disco, ed è questo che permette a due canali della stessa app (per esempio Android Studio Canary e Beta) di restare separati invece di essere sommati. Il prezzo è che rinominando un’app il suo passato resta sotto un nome che non esiste più. Quando OpenAI ha rinominato Codex in ChatGPT, 30 GB di download si sono divisi tra due voci che sembravano doppioni. Ora queste voci vengono raggruppate e attenuate in fondo all’elenco, sotto un’intestazione che spiega cosa sono. Non viene eliminato niente, e il totale continua a includerle.

## 0.3.57

**A un’app installata dall’App Store non viene più offerto il download diretto dello sviluppatore.** Molte app sono pubblicate in due posti contemporaneamente, sullo store e come download diretto dal sito dello sviluppatore, con la stessa identità ma come build davvero diverse. Il download diretto di solito è più avanti, perché non aspetta la revisione dello store. Per un’app installata dallo store DuoUpdater controlla prima lo store, ma quando quel controllo falliva per qualsiasi motivo (una connessione interrotta, uno store che non rispondeva) passava in silenzio al sito dello sviluppatore e ti offriva quello che trovava lì. WhatsApp lo mostrava come “26.32.75 → 26.33.19”: una versione reale, dal posto sbagliato. Accettarla avrebbe sostituito la tua copia dello store con una che l’App Store non avrebbe mai più potuto aggiornare. Ora le app installate dallo store vengono controllate sullo store e da nessun’altra parte.

**Cambiare il canale di aggiornamento di un’app dall’interno dell’app ora viene rilevato subito.** Alcune app ti permettono di scegliere tra le release normali e quelle beta (Surge, Tailscale, Fork, OrbStack, IINA, Alfred e altre) e DuoUpdater segue quella che hai scelto, così non ti offre mai una build che non hai chiesto. Prima però si accorgeva del cambio solo quando chiudevi l’app o aprivi una delle finestre di DuoUpdater. Nessuna delle due cose corrisponde a quello che si fa davvero: disattivare l’impostazione, lasciare l’app aperta e dare un’occhiata alla barra dei menu. Peggio ancora, le app salvano quell’impostazione sul disco quando pare a loro e non nel momento in cui fai clic (Surge qui ci ha messo cinque minuti), quindi anche alla chiusura poteva essere letta troppo presto. Ora DuoUpdater osserva direttamente le modifiche all’impostazione e ricontrolla quell’unica app entro un paio di secondi. Se riporti Surge alle release normali, la versione beta sparisce subito dalla sua riga, invece di restarci fino a un’ora.

**Un controllo che non è riuscito a raggiungere niente non sembra più un esito tutto in regola.** Quando tutte le fonti fallivano (niente rete, o un proxy che rifiutava le connessioni senza dirlo mentre l’icona del Wi-Fi diceva che era tutto a posto), le app non controllate venivano nascoste e il pannello diceva “127 app · aggiornate”. È la stessa schermata che vedi quando è tutto davvero aggiornato, e così un controllo fallito era indistinguibile da uno riuscito. Ora il pannello dice quante app non è riuscito a raggiungere, mostra cosa è andato storto e propone di riprovare con quelle, solo quelle, lasciando stare tutte quelle che è riuscito a controllare.
