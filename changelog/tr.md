# Yenilikler

Bu, `CHANGELOG.md` dosyasının Türkçe çevirisidir. Geçerli olan İngilizce sürümdür; burada yer almayan eski sürümler otomatik olarak İngilizce gösterilir.

## 0.4.5

**blender.org’dan indirilen Blender artık tek tıkla güncelleniyor.** Önceden yalnızca Homebrew ile kurulmuş kopya denetleniyordu.

**Blender’ın alfa, beta ve sürüm adayı (RC) derlemeleri kendi kanallarını izliyor.** DuoUpdater hangi tür derlemeye sahip olduğunuzu anlıyor ve aynı türden daha yeni bir derleme çıktığında haber veriyor. Bir alfaya asla kararlı sürüm önerilmiyor, tersi de geçerli.

**Muse güncellemeleri yeniden görünüyor.** Muse indirme bağlantısı için oturum açmayı istemeye başladığından beri, satırında yeni sürüm yerine bir hata görünüyordu.

**Perde arkasında.** Menü çubuğu açılır penceresi ve çalışma alanı, açılıştan sonraki ilk seferde biraz daha hızlı açılıyor; `duo check` de artık her şeyin güncel olduğunu söylemek yerine denetimi başarısız olan uygulamaları listeliyor.

## 0.4.4

**DuoUpdater artık İtalyanca, Geleneksel Çince, Portekizce (Brezilya) ve Türkçe konuşuyor.** Böylece toplam on bir dil oldu. Almanca, İspanyolca ve Japonca’daki yanlış veya kesik metinler düzeltildi. Ayarlar → Klasörler artık klasör adlarını Finder’ın sizin dilinizde gösterdiği gibi gösteriyor.

**Homebrew ile yüklediğiniz uygulamalar artık Homebrew üzerinden güncelleniyor.** Bu, brew ile yüklenmiş ve kendi güncelleyicisi de olan uygulamaları kapsar. Önceden DuoUpdater bunları doğrudan güncelliyor, Homebrew bundan haberdar olmuyordu; bir sonraki `brew upgrade` de zaten sahip olduğunuz sürümü yeniden indirip yüklüyordu.

**Pencereler bulunduğunuz Space’te açılıyor.** Önceden Ayarlar’ı veya başka bir DuoUpdater penceresini kapatıp yeniden açmak, sizi pencerenin en son gösterildiği Space’e geri geçirebiliyordu.

**Bir güncelleme, bir bildirim.** Bazı uygulamalar iki kaynak üzerinden denetleniyor ve bu kaynaklar aynı yeni sürümü tekrar tekrar duyurabiliyordu.

**Sürüm Günlüğü artık tarihi gelecekte olan sürümler göstermiyor.** Bir geliştiricinin akışı, DuoUpdater’ın sürümü ilk gördüğü andan daha sonraki bir tarih verirse, günlük o anı kullanıyor.

**Yedekleme diski takılı değilken çalışma alanı penceresi yeniden ekrana sığıyor ve Şimdi Kopyala neden kopyalayamadığını söylüyor.** Önceden pencere ekrandan uzun olabiliyor, listeler sonuna kadar kaydırılamıyordu; Şimdi Kopyala da hiçbir şey söylemeden hiçbir şey yapmıyordu.

## 0.4.3

**Xcode betaları ve sürüm adayları artık tek tıkla güncelleniyor.** Ayarlar → Xcode’da Apple Developer hesabınızla bir kez oturum açın; DuoUpdater yeni betaları ve RC’leri diğer tüm güncellemeler gibi indirip yükler. Önceden yalnızca yenisinin çıktığını haber verebiliyordu.

**İstediğiniz Xcode sürümünü mevcut olanların yanına yükleyin.** Ayarlar → Xcode tüm Xcode sürümlerini sürüm numarasına göre gruplanmış olarak listeler; macOS sürümünüze uyan grup zaten açık gelir. Yükle, seçtiğiniz sürümü Uygulamalar klasörüne ayrı bir kopya olarak koyar (örneğin Xcode-26.6.app) ve hiçbir şeyin yerine geçmez. İsterseniz yalnızca arşivi (.xip) de kaydedebilirsiniz. Oturum açtığınızda Apple’ın kendi listesi de dahil edilir; böylece yeni sürümler birkaç dakika içinde görünür.

**Apple Developer oturumunuz kendi kendini açık tutuyor.** Apple bir geliştirici oturumunu yaklaşık sekiz saat sonra sonlandırır. Apple bu Mac’i tanımaya devam ettiği sürece DuoUpdater artık arka planda, pencere açmadan ve parola sormadan yeni bir oturum alıyor. Bunu Ayarlar → Xcode’dan kapatabilirsiniz.

**Yeni Xcode sürümleri daha erken görünüyor.** Hafta içi, Apple’ın olağan yayın saatlerinde DuoUpdater beş dakikada bir yeni bir Xcode çıkıp çıkmadığına bakıyor.

**Geliştiricileri bazı şeyleri değiştirdikten sonra çalışmayan birkaç uygulama yeniden çalışıyor.** CapCut beta ve Superconductor nightly yeniden bulunup yükleniyor; Superconductor mevcut uygulama kimliğini de koruyor. VLC 3.0.24 ve JetBrains Air sürüm notlarını yeniden gösteriyor.

## 0.4.2

**Qoder CN IDE artık destekleniyor.** Qoder IDE’nin Çin anakarası baskısı güncelleme denetimi, tek tıkla yükleme ve pencerede sürüm notları alıyor. Masaüstü uygulaması Qoder CN de artık sürüm notlarını gösteriyor.

**Qoder IDE en son sürüm konusunda artık fikir değiştirmiyor.** Qoder güncellemeleri kademeli olarak dağıtıyor; DuoUpdater artık sizin IDE kopyanızla aynı şekilde soruyor ve bu yüzden her seferinde aynı yanıtı alıyor. Önceden sunulan sürüm iki sürüm arasında gidip gelebiliyor, yanıt değiştiği için tek tıkla yükleme de yarıda kalabiliyordu.

**İndirdikleri güncelleme sonradan eskiyen Sparkle uygulamaları yeniden güncellenebiliyor.** Sparkle ile kendini güncelleyen bir uygulama bir derleme indirmişse ve ardından daha yenisi çıkmışsa, DuoUpdater artık eski indirmeyi temizleyip en yenisini yüklüyor. Önceden Güncelle, şimdi yüklemenin geri alınacağını söyleyip duruyor ve satır hiç değişmiyordu.

**`duo install`, en son derleme zaten hazır beklerken bunu size söylüyor.** Bir uygulamanın kendi güncelleyicisi en son sürümü zaten indirmişse artık bunu belirtiyor ve uygulamadan çıkmanızı ya da `duo restart` çalıştırmanızı öneriyor. Önceden, uygulamanın yüklenemeyeceğini, yalnızca denetlenebileceğini yanlışlıkla söylüyordu.

## 0.4.1

**搜狗输入法 artık tek tıkla güncelleniyor.** DuoUpdater güncellemeyi, giriş yönteminin kendini güncellediği şekilde uyguluyor — yüklü paketi yerinde bırakarak — ve önce sözlüğünüzün ve ayarlarınızın bir kopyasını alıyor; böylece geri alma bunları da geri getiriyor.

**Başka bir diskteki yedekler artık giriş yönteminin sözlüğünü ve ayarlarını da saklıyor.** Önceden yedek diskine yalnızca uygulamanın kendisi taşınıyordu; bu yüzden bir giriş yöntemini oradan geri almak, yeni sürümün verilerini geride bırakıyordu.

**Asla yüklenemeyecek güncellemeler artık yok.** JetBrains Air artık Toolbox’ın gerçekten sunduğu derlemeyi gösteriyor. Geliştiricisi adını değiştirdikten sonra eski adıyla geride kalan bir App Store uygulaması, yalnızca diğer kopyayı yeniden yükleyen bir güncelleme sunmak yerine artık App Store’un hangi kopyayı güncellediğini söylüyor.

**Daha fazla uygulamanın sürüm notları biçimlendirilmiş olarak görünüyor.** Notlarını Markdown olarak yayımlayan uygulamalar artık diğer herkesle aynı yerel liste görünümünü alıyor. Önceden bu notlar düz metin olarak görünüyordu.

## 0.4.0

**Yeniden Başlat artık bir uygulamanın kendi yükleyicisiyle çakışmıyor.** Bir uygulama kendi güncellemesini indirmişse ve geri alma yedeğinin harici bir diske alınması gerekiyorsa, bu kopya artık yükleyici işini bitirene kadar bekliyor. Önceden, macOS’un yükleyiciye işini yapması için tanıdığı o birkaç saniye içinde çalışıyordu.

## 0.3.99

**Geri alma yedekleri artık başka bir diskte durabiliyor.** Bir yedek, uygulamanın eksiksiz bir kopyasıdır ve başlangıç diskinde bunlar hızla birikir. Ayarlar → Yedekler bağlı diskleri her birindeki boş alanla birlikte listeler, mevcut yedeklerinizi oraya taşır ve yenilerini arka planda oraya yazar — diski çıkarırsanız yalnızca bir gecikme yaşarsınız, geri alma noktanızı kaybetmezsiniz. `duo backups` komutuna `disks`, `sync`, `verify` ve `probe` eklendi.

**千问输入法 artık destekleniyor.** DuoUpdater yeni bir sürüm çıktığında haber veriyor ve giriş yöntemini, kendi kendini güncellediği şekilde güncelliyor.

**Sürüm notları artık önceki sürümde takılı kalmıyor.** Bir geliştirici bir güncellemeyi, değişiklik günlüğü sayfasında anmadan birkaç dakika önce yayımladığında, eski notlar yeni sürümün altına kaydediliyor ve sonsuza dek öyle kalıyordu. CleanShot X, 5.0.1 çıktığı günden beri onun altında 5.0’ın notlarını gösteriyordu.

**Bir yedeği silmek artık söylediği kadar yer açıyor.** DuoUpdater’ın eski sürümlerinin aldığı yedekler, macOS’un silmeyi reddettiği bir biçimde yazılmıştı; bu yüzden Temizle, kopyanın büyük kısmını diskte bırakırken o alanı geri kazanılmış sayıyordu.

**Temizle hemen açılıyor.** Önceden her bastığınızda saklanan tüm yedekleri baştan ölçüyordu.

**WorkBuddy en yeni sürümünü yeniden gösteriyor.** Güncelleme hizmeti en yeni derleme yerine bir yükseltme zincirinin bir sonraki adımıyla yanıt veriyor; bu yüzden WorkBuddy’nin dört baskısı da iki sürüm geriden geliyordu.

**Perde arkasında.** Hangi ikili dosyayı çalıştırdığını hiç bildirmeyen uygulamaların — Meta’nın Muse’u da bunlardan biri — çerçeveleri ve SDK’sı artık yine de okunuyor.

## 0.3.98

**Yeniden Başlat ile tamamlanan güncellemeler artık geri alınabiliyor.** Bir uygulama kendi güncellemesini zaten indirmişken Yeniden Başlat’a basarsanız, DuoUpdater artık önce mevcut sürümü kaydediyor; böylece bu güncelleme de diğerleri gibi Geri Alma altında görünüyor. Önceden yalnızca DuoUpdater’ın kendi yüklediği güncellemeler geri alınabiliyordu.

**Bir güncellemenin uygulamanın içinde neleri değiştirdiğini görün.** Önceki sürümü kaydedilmiş her uygulama için çalışma alanında artık Sürüm Notları’nın yanında bir Paket Farkı görünümü var: imzalama ve izinler, gereken en düşük macOS sürümü, arka plan ve giriş öğeleri, paketle gelen kitaplıklar ve eklenen, kaldırılan ya da boyutu değişen dosyalar. `duo diff` aynısını Terminal’de, bir uygulamanın herhangi iki kopyası için yapıyor.

**Yeniden Başlat, bir uygulamanın kendi güncelleyicisi güncellemeyi uygulamadığında bunu size söylüyor.** Uygulama kapanır ama güncelleme gerçekleşmezse satır artık bunu belirtiyor ve Yeniden Başlat’ı sunmaya devam ediyor. Önceden dönen gösterge tek söz etmeden duruyordu.

**Cherry Studio en yeni sürümünü yeniden gösteriyor.** Cherry Studio Mac indirmelerinin adlarını değiştirdikten sonra DuoUpdater daha eski bir sürümü en yenisi sanıyordu; bu yüzden yeni kopyalar “güncel” görünüyor, eski kopyalara ise o eski derleme sunuluyordu.

**App Store güncellemeleri artık yanıt vermeyen bir yardımcı yüzünden takılmıyor.** DuoUpdater’ın yardımcısı yanıt vermeyi bıraktığında güncelleme %0’da kalıyor, arkasında sıraya giren tüm App Store güncellemeleri de siz DuoUpdater’dan çıkana kadar bekliyordu.

**Tümünü Güncelle artık yok saydığınız uygulamaları yeniden başlatmıyor.** “Güncellenen uygulamaları otomatik yeniden başlat” açıkken, toplu işlemin sonunda yok sayılan bir uygulama ya da indirilmiş sürümünü atladığınız bir uygulama kapatılıp yeniden açılabiliyordu.

**Tinycast ve SuperCmd artık destekleniyor.** DuoUpdater, Tinycast’in ya da betasının yeni bir sürümü çıktığında haber veriyor; ayrıca SuperCmd 2’nin yanında özgün açık kaynak SuperCmd uygulamasını da artık tanıyor. Kimi Code’un sürüm notları da artık görünüyor.

**Sürüm notları sunulan sürümle eşleşiyor.** VS Code’un en son sürüm notları sayfası boş geliyordu; yeni bir sürüm çıktıktan hemen sonra da not bölmesi onun yerine önceki sürümü gösterebiliyordu.

**Sürüm Günlüğü artık her açılışta aynı sürümü yeniden eklemiyor.** Claude, Raycast ve Cline gibi uygulamalarda DuoUpdater her başladığında bir yinelenen kayıt daha oluşuyordu.

**Çalışma alanının kenar çubuğu Uygulamalar, Brew ve Geri Alma sekmelerine ayrıldı.** Geçiş yapmak için bir sekmeye tıklayın ya da sekmelerin üzerinde sürükleyin; arama üçünü birden daraltır.

**Perde arkasında.** Aynı uygulamada Yeniden Başlat ile Geri Al artık birbirine karışmıyor; bir güncelleme akışı artık DuoUpdater’a indirme klasörünün dışındaki dosyaları sildiremiyor; arka plan denetimleri artık macOS’un diğer uygulamaların verilerine erişim izni istemesine yol açma riski taşımıyor; İstekler filtresine girilen çok büyük bir sayı artık uygulamayı kapatmıyor; menü çubuğu da artık `duo install` sırasında reddettiğiniz yönetici istemine uyuyor.

## 0.3.97

**iStat Menus güncellemeleri doğru algılanıyor.** iStat Menus bir güncellemeyi yeniden yayımladığında DuoUpdater, güncelleme yüklendikten sonra da onu sunmaya devam edebiliyor, Güncelle’ye yeniden basmak ise bir hatayla sonuçlanıyordu.

**Memoh Desktop artık destekleniyor.** DuoUpdater yeni bir sürüm çıktığında haber veriyor ve uygulamayı tek tıkla güncelleyebiliyor.

**Tümünü Güncelle artık zaten yeniden açılmış bir App Store uygulamasını yeniden başlatmanızı istemiyor.** App Store bir uygulamayı kapatıp yeni sürümüyle yeniden açtığında, uygulamanın satırı artık tüm toplu işlem bitene kadar “Şimdi yeniden başlat” demek yerine onu hemen güncellenmiş olarak gösteriyor.

## 0.3.96

**Kendi güncellemesini zaten indirmiş bir uygulamanın güncellemesi artık iki kez indirilmiyor.** Bazı uygulamalar bir güncellemeyi arka planda sessizce indirir ve ardından onları yeniden başlatmanızı bekler. DuoUpdater’da Güncelle’ye bastığınızda artık diskinizde hazır bekleyen kopya yükleniyor: güncelleme saniyeler içinde tamamlanıyor ve hiçbir şey indirmek gerekmiyor. Önceden DuoUpdater aynı sürümü baştan indiriyordu.

**Cua Driver ve Petex artık destekleniyor.** DuoUpdater ikisinden birinin yeni bir sürümü çıktığında haber veriyor; Cua Driver ayrıca tek tıkla güncelleniyor ve sürüm notlarını gösteriyor.

**Aynı güncelleme için artık tekrar tekrar bildirim gelmiyor.** Bir geliştiricinin sunucusu iki sürüm arasında gidip geldiğinde her denetim yeni bir güncelleme gibi görünüyor ve bir bildirim daha gönderiliyordu.

**Az önce yüklenmiş bir paket artık yeniden yüklenmeyi önermiyor.** Satırı, indirilen paketin yeniden açılacağını söyleyip duruyordu.

**DuoUpdater artık macOS 15 Sequoia veya sonrasını gerektiriyor.** Hâlâ macOS 14 kullanan bir Mac mevcut sürümünde kalıyor ve ona artık güncelleme sunulmuyor; Apple Silicon’lu her Mac desteklenen bir macOS sürümüne yükseltilebilir.

**Perde arkasında.** Olağan denetimler artık indirme bağlantılarını önceden aramıyor; bu, bir geliştiricinin indirme sunucusu her zaman aşımına uğradığında çalışan bir Güncelle düğmesini kısa süreliğine gizleyebiliyordu.

## 0.3.95

**Aside artık destekleniyor.** DuoUpdater, Aside tarayıcısının yeni bir derlemesi çıktığında haber veriyor ve sürüm notlarını gösteriyor.

**macOS sürümünüzün çalıştıramayacağı güncellemeler artık sunulmuyor ve satır bunun nedenini söylüyor.** Bir geliştirici bir sürümün hangi macOS sürümlerini desteklediğini belirttiğinde DuoUpdater buna uyuyor: macOS yükseltmesinden sonra Little Snitch artık desteklediği en yüksek macOS sürümü sisteminizin altında kalan bir derleme sunmuyor; Xcode artık sizinkinden daha yeni bir macOS gerektiren bir derleme sunmuyor; uygulaması daha yeni bir macOS gerektiren bir yükleyici paketi de açılmayacak bir uygulamayı yüklemek yerine reddediliyor. Önceden boş bir tire gösteren satırlarda artık “Bu macOS için henüz değil” ya da “Daha yeni bir macOS gerekiyor” yazıyor; ayrıntılar bir tık uzakta.

**Her uygulamanın hangi SDK ile geliştirildiğini görün.** Bir uygulamanın adının yanındaki işarete tıklayın; ayrıntılarda artık örneğin “macOS 27.0 SDK’sı ile geliştirildi.” yazıyor — hangi uygulamaların en son macOS için yeniden derlendiğini anlamak için kullanışlı.

**İki paket halinde gelen Homebrew uygulamaları — biri eski sistemler, biri en yenisi için — artık doğru paketten okunuyor.** OnyX macOS 27 için bu şekilde ikiye ayrılıyor ve DuoUpdater yalnızca eski sistemlere yönelik pakete bakıyordu: ya OnyX için hiçbir şey göstermiyor ya da onu, Homebrew’un 27’ye yüklemeyi reddettiği bir sürüme göre güncel sayıyordu. Artık ikisinden hangisini yüklediyseniz DuoUpdater onu izliyor.

**TestFlight betaları, TestFlight açıldığında artık güncellemelerini kaybetmiyor.** Yeni bir derlemesi bekleyen bir beta “güncel” durumuna düşebiliyor ve TestFlight’ı yeniden açana kadar öyle kalıyordu.

**Dropbox ve ToDesk için tek tıkla güncellemeler doğru dosyayı indiriyor.** Apple Silicon’da Dropbox yalnızca Intel’e yönelik derlemeyi indiriyor, güvenlik denetimi de bunu reddediyordu; ToDesk’e ise genel sürümü yerine yalnızca bazı kullanıcılara dağıttığı erken erişim derlemesi sunuluyordu.

**Yeniden Başlat, Spotify’ın güncellemesini hemen tamamlıyor.** Spotify kendi güncellemesini zaten indirmişse Yeniden Başlat, güncelleme gerçekleşene kadar dakikalarca dönüp duruyordu.

**Beta derlemeleri, dönüştükleri sürümlere geçiyor.** Bir Xcode betasına güncel görünmek yerine sürüm adayı sunuluyor, CotEditor betaları sürüm adaylarını görüyor, test döngüsü sona ermiş bir Carbon Copy Cloner betasına da başarısız bir denetim yerine dönüştüğü sürüm sunuluyor.

**Sürüm notları sahip olduğunuz sürümle eşleşiyor.** Blender 5.2 önceden 5.1’in notlarını, Raycast 1.x ise 2.x’in notlarını gösteriyordu. Gemini’deki “Sayfayı aç” artık bir hata yerine Google’ın güncel masaüstü sayfasını açıyor.

**Ayarlar her seçeneği hemen yanında açıklıyor.** Bölümlerin altındaki uzun notların yerini her denetimin altında kısa bir satır aldı; seçiciler de yalnızca seçtiğiniz seçeneği açıklıyor.

**Uygulama artık adını DuoUpdater olarak yazıyor**, web sitesiyle aynı şekilde.

## 0.3.94

**Güvenmediğiniz tap kaynaklarından gelen Homebrew paketleri yeniden görünüyor.** Homebrew 6’dan beri brew, yüklü olanları listelerken güvenilmeyen tap kaynaklarındaki paketleri sessizce atlıyor; bu yüzden bu paketler DuoUpdater’dan hiçbir açıklama olmadan kayboluyordu. Artık “Denetlenmedi · tap güvenilir değil” olarak, kopyalanmaya hazır `brew trust` komutuyla birlikte listeleniyorlar — Terminal’de bu komutu (ya da bir yükseltmeyi) çalıştırdıktan sonra pencereye geri döndüğünüz anda pencere de durumu yakalıyor.

**Kendini güncellemek için yönetici parolası gereken uygulamalar artık iki kez güncellenmiyor.** Tailscale gibi bir uygulama kendi güncellemesini zaten indirip yeniden başlatılmayı beklerken DuoUpdater bunu göremiyor ve yine Güncelle’yi sunuyordu; bu da uygulamanın kendi yükleyicisiyle çakışabiliyordu. Satır artık onun yerine Yeniden Başlat’ı sunuyor, Tümünü Güncelle de bu uygulamaya dokunmuyor.

**Homebrew bölümü artık Homebrew’un kendisini güncelleyebiliyor.** Yeni bir Homebrew sürümü çıktığında en üstteki bir satır, `brew update` komutunu sizin için çalıştırmayı öneriyor. `HOMEBREW_NO_AUTO_UPDATE` ayarladıysanız bu satır gizli kalıyor.

**Başarısız bir Homebrew yükseltmesi artık brew’un asıl hatasını gösteriyor.** Satır önceden brew’un hatadan sonra yazdırdığı öneriyi gösteriyor ya da hiçbir şey göstermiyordu; bu yüzden “Command Line Tools’unuz çok eski” gibi bir mesaj size hiç ulaşmıyordu. Birkaç paketi aynı anda yükseltirken de işlem artık bitmeden bitti diye bildirilmiyor.

**Menü çubuğu simgesi 50’nin ötesini sayıyor.** 50’den fazla güncelleme beklerken simge 50’de kalıyordu.

**Sürüm notları: Claude’unkiler, Claude’un kendisinin gösterdiği gibi Yeni, İyileştirildi ve Düzeltildi başlıkları altında gruplanıyor; Mac Mouse Fix’inkiler gömülü bir sayfa yerine metin olarak görünüyor; Homebrew’un kendi uygulamasının da artık notları var.**

**`duo check` artık gerçekte denetleyemediği durumlarda “Everything is up to date.” demiyor.** TestFlight’ı okuyamadığında ya da uygulama taraması yarıda bırakıldığında artık bunu belirtiyor.

## 0.3.93

**Bir uygulama sürüm notlarını birkaç dilde yayımlıyorsa, notlar artık sizin dilinizde görünüyor.** Bazı uygulamalar notlarını her sürümle birlikte çevirileriyle yayımlıyor. DuoUpdater önceden, uygulama hangi çeviriyi ilk ya da son sıraya koyduysa onu alıyordu; bu yüzden bir uygulamanın notları herkese Almanca görünüyor, bir diğerininki ise sürümden sürüme dil değiştiriyordu.

**Mac sürümü ekleyen uygulamalar artık “bu Mac’te desteklenmiyor” olarak görünmüyor.** Apple Silicon’da çalıştırdığınız bir iPhone ya da iPad uygulaması, geliştiricisi gerçek bir Mac derlemesi yayımladığı anda yanlışlıkla işaretleniyordu — oysa bu, güncellemeyi daha az değil, daha çok erişilebilir kılan tek değişiklikti.

**Beta testine de katıldığınız bir App Store uygulaması artık TestFlight derlemesi sanılmıyor.** Bir geliştirici bir betayı hiç değiştirmeden yayına aldığında ikisi aynı derleme numarasını taşıyor ve satın aldığınız kopya TestFlight’a atanıyordu — bu yüzden App Store ona hiçbir zaman güncelleme sunamıyordu.

**Kullandığınızdan daha yeni bir macOS gerektiren bir App Store güncellemesi artık bunu söylüyor.** Önceden satır yine de yüklemeyi öneriyor, App Store son adımda reddediyor ve ekranda nedenini açıklayan hiçbir şey olmuyordu.

**İstekler penceresi artık günlüğünün gerçekte ne kadar geriye gittiğini gösteriyor ve tam olarak kapsayamadığı tarih aralıklarını işaretliyor.** Önceden, yalnızca birkaç saat geriye giden bir günlükte “Son 30 gün”ü seçmek, “Son 24 saat”i seçmekle tamamen aynı görünüyordu ve ekranda nedenini açıklayan hiçbir şey yoktu.

**TestFlight betaları konusunda DuoUpdater’ın ne kadar iş yapacağını Ayarlar → Genel’de siz seçiyorsunuz.** *Ben yenilediğimde* seçeneği TestFlight’ın zaten bildiklerini okur ve Yenile’ye bastığınızda ondan güncel bir yanıt ister. *Güncel tut* buna ek olarak DuoUpdater’ın kendiliğinden sormasına da izin verir: böylece TestFlight’ın arka planda yüklediği bir beta siz yenileyene kadar soru işareti olarak kalmaz, sizi bekleyen bir derleme de bir “güncel” ibaresinin arkasında gözden kaçmaz. *Kapalı* hiçbir şey okumaz; tahmin yürütmek yerine bu satırlarda bunu açıkça belirtir. Tam Disk Erişimi zaten verilmiş Mac’ler *Ben yenilediğimde* ile, diğer herkes *Kapalı* ile başlar.

**TestFlight’ı kendiniz açmanız, DuoUpdater’ın onun yüklediklerini fark etmesi için artık yeterli.** TestFlight üzerinden yüklediğiniz bir beta, bir sonraki yenilemeye kadar soru işareti olarak kalıyordu — TestFlight’ın “Test Etmeye Hazır” bildiriminin zaten sahip olduğunuz uygulamalar için artık gelmediği macOS 27’de bu, saatler sürebiliyordu.

**Cline artık hem kararlı hem de beta derlemelerinde güncelleme alıyor ve sürüm notlarını gösteriyor.** Şimdiye kadar sürüm numarası yerine bir soru işaretiyle duruyordu — DuoUpdater’ın okuyabileceği türden bir güncelleme akışı yayımlamıyor, Homebrew paketi de yok. DuoUpdater artık Cline’ın kendi güncelleyicisinin sorduğu adrese soruyor; böylece sunulan güncelleme, Cline’ın kendi kendine yükleyeceği güncellemenin aynısı oluyor ve beta derlemesi beta hattında kalıyor.

**Değişiklikleri Added ve Fixed gibi başlıklar altında gruplayan sürüm notları artık bu başlıkları koruyor.** Önceden tüm gruplar tek, düz bir listede birleştiriliyordu; bu yüzden hangi değişikliklerin yeni özellik, hangilerinin hata düzeltmesi olduğunu ayırt edemiyordunuz.

**Mac Mouse Fix’in kendi Genel ayarlarında “Get Beta Versions” seçeneğini açtıysanız, uygulamanın beta sürümleri artık size sunuluyor.** Önceden DuoUpdater yalnızca Mac Mouse Fix’in normal sürümlerini görebiliyordu; bu yüzden bir beta derlemesi, bir sonraki normal sürüm çıkana kadar fark edilmeden kalıyordu.

**Derleme numarası düz bir sayaç olan uygulamalar artık kendi yama sürümlerini gizlemiyor.** 12.10 gibi bir sürümü 282987 derleme numarasıyla bildiren bir uygulamada 12.10.1 sürümü “zaten güncel” olarak görünüyordu.

**Aynı sürüm adını koruyan bir uygulamanın yeni derlemesi yeniden duyuruluyor.** Bir derleme bir kez duyurulduktan sonra aynı ad altındaki sonraki tüm derlemeler sessizce geliyordu — satır vurgulanıyor, simgedeki işaret onu sayıyor, ama hiçbir bildirim görünmüyordu.

**“Tümünü Güncelle” artık yalnızca gerçekten güncellenen uygulamaları sayıyor.** İşlemi sizin bitirmeniz için Apple’ın Yükleyici’sini açan bir uygulama, penceresi hâlâ açıkken tamamlanmış sayılıyordu; bu yüzden “2 uygulama güncellendi” mesajı, henüz hiçbir şeyin değişmediği anlamına gelebiliyordu.

**Yüklenen ama geride bir kalıntı bırakan bir güncelleme artık “Uygulama Yönetimi izni verin” olarak değil, yüklendi olarak bildiriliyor.** Satır sizi Sistem Ayarları’na yönlendirirken yeni sürüm zaten çalışıyordu.

**“Tümünü Güncelle”yi durdurmak artık süren indirmeyi de durduruyor.** Önceden gigabaytlarca büyüklükteki bir aktarım sonuna kadar devam ediyor, beş kereye kadar yeniden deniyor ve ancak ondan sonra iptal edildiğini fark ediyordu.

**Tek bir değişiklik günlüğü sayfasını paylaşan iki uygulamanın sürüm notları artık karışmıyor; notları sürüm başına ayrı sayfalarda duran uygulamaların notları da güncellemeden sonra güncel kalıyor.** Antigravity ve Antigravity IDE on beş dakika boyunca birbirinin notlarını gösterebiliyordu; Thunderbird, WeChat, Opera ve birkaç uygulama daha, güncellemeden sonra bir süre önceki sürümün notlarını göstermeye devam ediyordu.

**Uygulama listesinde arama, Ayarlar’daki arama gibi artık aksanları yok sayıyor.** “cafe” yazdığınızda artık “Café” bulunuyor.

**Tanılama sayfası artık her sürüm kanalı için ayrı bir sağlık satırı gösteriyor.** Bozuk bir beta ya da önizleme kuralı önceden sağlıklı kararlı kardeşinin arkasında gizli kalıyordu.

**GitHub’ın “forbidden” yanıtı artık hız sınırı olarak bildirilmiyor.** Gizli hale getirilen bir depo ya da bir yetki kapsamı eksik olan bir token, önceden sizi hiçbir işe yaramayacak bir token eklemeye yönlendiriyordu.

**Bekleyen derlemesi çalışandan daha eski olan, kendini güncelleyen bir uygulama için artık Yeniden Başlat sunulmuyor.**

**Perde arkasında.** Yüklemeler, yedeklemeler ve paket denetimleri artık uygulamanın geri kalanının çalıştığı iş parçacıklarını meşgul etmiyor; böylece bunlardan biri sürerken menü yanıt vermeye devam ediyor. Büyük bir indirme sürerken de menü akıcı kalıyor. Sürüm Günlüğü, bir üreticinin tek bir sürüm adı altında yayımladığı her sürümü sayıyor. Uygulamanın kendi yürütülebilir dosyası eksik kalacaksa geri alma yedeği saklanmak yerine reddediliyor. Yeni bir Mac’teki ilk açılış artık günlüğe asılsız veritabanı hataları yazmıyor. `duo verify` ve `duo reconcile` artık kayıtları bozulup tek parçaya çöken bir değişiklik günlüğünü ve günlerdir başarısız olan bir yükleyici adresini bildiriyor. Takılan bir `duo` komutu da askıda kalmak yerine yirmi saniye sonra taramasından vazgeçiyor.

## 0.3.92

**Kendini güncelleyen bazı uygulamalar, daha yeni bir sürüm çıkmışken artık güncel görünmüyor.** Güncelleme bilgileri geç yenilenen bir indirme sunucusunun arkasında duran uygulamalarda DuoUpdater, bir sürüm çıktıktan sonra günlerce eski sürümü görmeye devam edebiliyordu.

**Kimi’nin sürüm notları artık DuoUpdater’da görünüyor.**

**CodeEdit güncellemeleri artık görünüyor.** Daha yeni bir CodeEdit sürümü, güncellemeyi sunmak yerine satırını soru işareti olarak bırakıyordu.

**Perde arkasında.** Menüdeki Homebrew listesi daha hızlı doluyor, `duo` komutları da daha hızlı başlıyor.

## 0.3.91

**Bir TestFlight betasında Yeniden Denetle artık gerçek yanıtı veriyor.** Önceden satırı bir sonraki yenilemeye kadar soru işaretine çeviriyordu.

**Yenile düğmesi TestFlight’a danışırken TestFlight betaları yanıtlarını koruyor.** Önceden birkaç saniyeliğine hepsi soru işaretine dönüşebiliyordu.

## 0.3.90

**super.engineering artık destekleniyor: güncelleme denetimi, sürüm notları ve tek tıkla yükleme.** Yeni bir nightly, içindeki değişikliklerle birlikte görünüyor ve Güncelle onu sizin için yüklüyor.

**Microsoft Edge Beta size kararlı bir Edge derlemesi sunabiliyordu.** Microsoft’un beta akışı kısa bir süre boş kaldığında satır kararlı bir sürüm gösteriyordu; güncellemek bu sürümü betanızın üzerine yazacaktı.

**TestFlight betaları artık TestFlight’ın onlar için sunduğu güncellemeleri gösteriyor; iPhone ve iPad uygulamalarının betaları da buna dahil.** Yenile düğmesi arka planda TestFlight’a danışıyor, bulunan bir güncelleme artık birkaç dakika sonra kaybolmuyor ve TestFlight düğmesi o betanın sayfasını açıyor.

**DuoUpdater bir TestFlight betasının güncel olup olmadığını anlayamadığında bunu söylüyor.** Satır onu güncel saymak yerine soru işareti gösteriyor — örneğin TestFlight’ta oturumunuz kapalıyken ya da o betayı artık test etmiyorken.

**Tam Disk Erişimi artık açıklanıyor ve bu izin olmadan hiçbir şey sizi rahatsız etmiyor.** Bu izin yokken DuoUpdater artık macOS’un diğer uygulamaların verilerinin okunmasıyla ilgili uyarılarını tetiklemiyor; bir TestFlight betası ya da CotEditor bu izne ihtiyaç duyarsa, nedenini ve iznin nereden verileceğini size bir kez söylüyor.

**Güncellenen bir uygulama kapandığında Yeniden Başlat kayboluyor.** Arkada bir yardımcı süreç bırakan bir uygulama, güncellemesi çoktan etkinleştikten sonra bile yeniden başlatılmayı istemeye devam ediyordu.

**Yanıtlanmamış bir macOS gizlilik istemi artık güncelleme denetimlerini durdurmuyor.** Denetim, o uygulamanın ayarı olmadan devam ediyor.

**Rockxy ve Ollama’nın sürüm notları yeniden eksiksiz.** Rockxy’ninkiler yalnızca en yeni sürümü değil, son sürümleri de kapsıyor; Ollama’nın en yeni sürümü de artık dışarıda kalmıyor.

**İsteğe bağlı komut satırı yardımcısı `duo`, TestFlight’ı daha iyi idare ediyor.** `--refresh-testflight`, TestFlight açık olsun ya da olmasın ekranınızı ele geçirmeden çalışıyor; `duo check` de TestFlight daha yeni bir derleme duyurmuşken bir betayı artık güncel saymıyor.

## 0.3.89

**Telegram Desktop yeniden güncelleme denetimi alıyor.** Telegram yayımladığı dosyanın adını değiştirdi ve satır artık bu addan bir sürüm okuyamıyordu — bu yüzden arkasında bekleyen güncelleme yerine bir denetim hatası gösteriyordu.

**Bir iPhone ya da iPad uygulamasının TestFlight derlemesi artık TestFlight derlemesi olarak tanınıyor.** DuoUpdater onu bir App Store satın alımı olarak okuyordu; bu yüzden satır uygulamayı kimin güncel tuttuğunu yanlış gösteriyor, mağazaya da var olmayan bir kayıt soruluyordu — uygulama yüklü kaldığı sürece her denetimde.

**TestFlight betası, TestFlight’ın kendi simgesiyle işaretleniyor.** App Store’un ilgilendiği satırlar zaten mağazanın simgesini taşıyordu; TestFlight’ın ilgilendiklerinde ise bunun yerine ad açıkça yazılıyordu, yani aynı türden satırlar iki farklı şekilde işaretleniyordu.

**Ağ penceresinin başlığı, sekme değiştirdiğinizde yerinde duruyor.** İki sekmenin başlıkları biraz farklı yüksekliklerdeydi; bu yüzden aralarında geçiş yapınca pencere seğiriyormuş gibi görünüyordu.

## 0.3.88

**Tüm uygulama listenizde kaydırma yeniden akıcı.** Tam listede hızlı kaydırma kare atlıyordu; artık her satır, önce oluşturulması gerekmeden yüksekliğini bildiriyor.

**Bir App Store uygulamasının sürüm notları artık her zaman App Store’dan geliyor.** Mağazanın bir uygulama için kendi sorgusu sonuç vermediğinde ya da başarısız olduğunda pencere, o uygulamanın diğer dağıtımının notlarına — kendi sürüm numaraları olan farklı bir derlemeye ait notlara — geri dönebiliyor ve sizin kopyanıza hiçbir zaman sunulmayacak bir sürümü anlatıyordu.

**Beta ya da Guinea Pig kanalındaki Windscribe’a o kanalın derlemeleri sunuluyor.** DuoUpdater, Windscribe’ın kendi ayarlarında hangi güncelleme kanalını seçtiğinizi okuyor; böylece bir ön sürüm hattını izleyen kopyaya, o hatta daha yeni derlemeler varken artık güncel olduğu söylenmiyor. Pencere ayrıca bu ön sürüm derlemelerinin notlarını da gösteriyor; önceden yalnızca kararlı olanlarınkini listeliyordu.

**Windscribe artık sürüm notlarıyla birlikte güncelleme denetimi alıyor.** Daha eski bir derleme çalıştıran bir kopya, geçebileceği sürümle ve o sürümdeki değişikliklerle listeleniyor; önceden DuoUpdater’ın Windscribe’ın sürümünü görmesinin hiçbir yolu yoktu. Güncelleme yine Windscribe’ın kendi yükleyicisiyle yapılıyor; bu yükleyici, uygulamanın kendisinin dışında duran parçalarını da kuruyor.

**Siz tıklarken ortadan kalkan bir uygulamaya artık güncelleme uygulanmıyor.** Uygulama, tıklamanızla yüklemenin başlaması arasında kaldırılır, değiştirilir ya da okunamaz hale gelirse DuoUpdater artık o konuma yine de yüklemek yerine durup bunu söylüyor.

**İsteğe bağlı komut satırı yardımcısı `duo`, bir paket yüklemesini artık bitmeden bitti saymıyor.** `.pkg` olarak gelen bir uygulamayı yüklemek macOS yükleyicisini açıp gerisini size bırakıyor, ama özet bunu yüklenmiş sayıyordu — henüz hiçbir şeyin yerine yenisi konmamışken “1 yüklendi”. Bunlar artık ayrı sayılıyor. `--json` çıktısı da artık her satırı o uygulamaya ne olduğuyla etiketliyor; böylece bir betik, bir başarısızlığı bilinçli bir atlamadan ayırt etmek için İngilizce açıklamayı okumak zorunda kalmıyor.

**Perde arkasında.** Tek tıkla Güncelle’yi koruyan yükleme öncesi yeniden denetim artık `duo install` komutunu da koruyor; bir indirmenin bir uygulamanın yerine geçmeden önce geçmesi gereken denetimler de bunları kullanan her iki yol için tek bir yerde tutuluyor.

## 0.3.87

**Bir güncelleme kaynağı kendisiyle çeliştiğinde Güncelle’ye tıklamak artık boşa gitmiyor.** Tıkladığınız anda çalışan denetim, satırın sunduğundan daha eski bir sürümle dönerse DuoUpdater artık bunu söylüyor ve güncellemeyi sunmaya devam ediyor. Önceden uygulamayı zaten güncel diye bildirip listeden çıkarıyor, aynı güncelleme de bir sonraki denetimde yeniden beliriyordu.

**Fork, Develop kanalına ayarlandığında güncellemeler yeniden sunuluyor.** DuoUpdater, Fork’un kanal ayarını ters okuyor ve epey geride kalan Stable akışını izliyordu — bu yüzden Fork’un kendisi daha yeni bir sürüm sunarken Develop kopyası güncel diye listeleniyordu.

**Mac Performance Monitor artık sürüm notlarını gösteriyor.** Uygulama notlarını bizim okuduğumuz akışta değil, deposunda yayımlıyor; bu yüzden pencerenin onun için gösterecek bir şeyi yoktu.

**CotEditor artık hem kararlı hem de beta hattında destekleniyor.** Bir kopyanın hangi hattı izlediği, çalıştırdığı sürümden ve CotEditor uygulamasının kendi “Update to prereleases when available” ayarından anlaşılıyor; böylece beta kopyaya, onu geriye götürecek bir kararlı sürüm yerine bir sonraki beta sunuluyor.

**App Store’dan yüklediğiniz bir uygulamaya asla başka bir yerden indirme sunulmuyor.** Mağazanın bu uygulama için kendi sorgusu başarısız olduğunda ya da boş döndüğünde satır artık, sürüm numarası vermeden, uygulamayı mağazanın yönettiğini söylüyor. Önceden denetim uygulamanın diğer dağıtımına — kendi sürüm numaraları olan farklı bir derlemeye — kayabiliyor ve onu mağaza kopyanızın üzerine yüklemeyi önerebiliyordu.

**Bir uygulamaya asla onu daha eski bir sürüme götürecek bir güncelleme sunulmuyor.** Bazı akışlar kararlı bir sürümü, aslında daha ileride olan bir ön sürümün üstünde listeliyor; onu almak uygulamayı geriye götürürdü.

**Bir satırdaki uzun hata artık listenin geri kalanını aşağı itmiyor.** İki satırla sınırlanıyor; tam metin, imleci üzerine getirince görünüyor.

## 0.3.86

**Dört uygulama daha destekleniyor: WhatCable, Qoder IDE, Qoder ve Yaak.** Her biri güncelleme denetimi ve tek tıkla yükleme alıyor; sürüm notları da pencereye gömülü bir sayfa olarak değil, metin olarak okunuyor.

**Qoder’ın iki Mac uygulaması birbirinden ayırt ediliyor.** IDE ile masaüstü uygulaması aynı adı ve aynı indirme sayfasını paylaşıyor ama ayrı sürüm hatlarında yayımlanıyor; bu yüzden artık her biri ayrı ayrı izleniyor.

**WhatCable ve Yaak’ın beta derlemeleri kendi hatlarında izleniyor.** Beta çalıştıran bir kopyanın önceden hiçbir kaynağı yoktu ve “Başarısız” durumunda kalıyordu; artık ona, kararlı sürümlerinkinden ayrı tutulan sürüm notlarıyla birlikte bir sonraki beta sunuluyor. WhatCable için buna, bir betanın sonunda dönüştüğü kararlı sürüm de dahil — onu almak kopyayı kararlı hatta geçiriyor.

## 0.3.85

**App Store uygulamalarınızı denetlemek eskisine göre çok daha az ağ trafiği kullanıyor.** Önceden her denetim her App Store uygulamasının ürün sayfasını yeniden indiriyordu; artık sayfalar bir saat saklanıyor ve mağazaya tüm uygulamalarınız, uygulama başına bir istek yerine birkaç istekle soruluyor. Beş dakikalık denetim aralığında bu, toplamda kabaca üçte bir daha az trafik demek; varsayılan altı saatlik aralıkta ise sayfaların süresi denetimler arasında yine doluyor, bu yüzden oradaki tasarruf daha küçük.

**Tek bir uygulamayı yeniden denetlemek artık tüm App Store uygulamalarını yeniden indirmiyor.** Tek bir “Yeniden Denetle” önceden önbelleğe alınmış tüm ürün sayfalarını atıyordu; bu yüzden bir sonraki zamanlanmış denetim hepsini baştan indirmek zorunda kalıyordu. Artık yalnızca sorduğunuz uygulamayı yeniliyor.

**GitHub üzerinden dağıtılan uygulamaları denetlemek eskisine göre çok daha az ağ trafiği kullanıyor.** Önceden her denetim, hiçbir şey yayımlanmamış olsa bile her sürümün tam açıklamasını yeniden indiriyordu; artık GitHub’a sürümün son seferden beri değişip değişmediğini soruyor ve değişmediyse hiçbir şey indirmiyor. Günde bir kez her sürümü baştan sona yeniden okuyor; böylece geri çekilen bir sürüm bir gün içinde fark ediliyor.

**GitHub’da beta ya da nightly hattında izlenen uygulamalar artık bir sayfa dolusu sürüm yerine tek bir sürüm istiyor.** Neredeyse her seferinde yanıt en yeni sürüm oluyor; tam sayfa yalnızca öyle olmadığı turlarda indiriliyor.

**Vorssaint’in güncelleme denetimi artık bir yönlendirmeye dayanmıyor.** Deposunun adı değişmişti ve eski adı izlemek, isteği sessizce GitHub’ın anonim hız sınırına düşürüyordu; denetim artık doğrudan yeni ada gidiyor.

**Perde arkasında.** Yayımlanan uygulama artık GitHub’ın barındırdığı bir Mac’te, herkesin doğrulayabileceği derleme kökeni kanıtıyla derleniyor, imzalanıyor ve noter onayından geçiriliyor; kaydedilen istek günlüğü de önbellekten gelen bir yanıtı ağdan gelenden ayırıyor.

## 0.3.84

**Dışa aktardığınız istek günlükleri artık hesap adınızı içermiyor.** Ana klasörünüzde yüklü bir uygulamanın her satırı önceden tam yolu açıkça yazıyordu; artık günlüğü hangi yolla dışarı alırsanız alın, onun yerine `~` gösteriliyor.

**İstekler sekmesi artık neyi kapsayıp neyi kapsamadığını söylüyor.** Burada DuoUpdater’ın kendi yaptığı istekler kaydediliyor. Bir sürüm notları sayfası kendi görsellerini ve yazı tiplerini kendisi yüklüyor; App Store ve Homebrew güncellemeleri de ayrı araçlarla yapılıyor — bunların hiçbiri orada görünmüyor ve pencere artık bunu sizin tahmininize bırakmak yerine açıkça söylüyor.

**URL’yi Kopyala artık verdiği adresteki özel karakterleri kodluyor.** Boşluk içeren yollar — aralarında Firefox, Thunderbird ve Bartender indirmeleri de var — olduğu gibi kopyalanıyordu; bir tarayıcı bunu hoş görür, komut satırı ise görmez.

**CapCut’ın beta satırı artık başarısız bir denetim bildirmiyor.** İki beta arasında — biri kararlı sürüme geçtikten sonra ve bir sonraki açılmadan önce — üreticisi o hatta hiçbir şey yayımlamıyor; bu da kırmızı bir satır ve işe yaraması mümkün olmayan bir Yeniden Dene olarak görünüyordu. Satırın artık bir sonraki beta çıkana kadar o kaynaktan bir yanıtı olmuyor, o kadar.

**Audacity artık neyle geliştirildiğini gösteren işareti gösteriyor.** Uygulama, yanındaki asıl programa devreden küçük bir başlatıcıyla açılıyor; işaret bu başlatıcıdan okunuyordu, o ise hiçbir kitaplığa bağlanmıyor.

**App Store sürüm notları artık sizin dilinizde geliyor.** Her zaman mağazanın varsayılan dilinde çekiliyorlardı; bu yüzden Çince ya da Japonca çalışan bir Mac’te bile İngilizce okunuyorlardı.

**DuoUpdater’ın kendi güncellemeleri artık Ağ penceresinde kendi adıyla görünüyor.** Sürüm denetimi, sürüm notları ve indirmesi, uygulama sütunu boş bırakılarak kaydediliyordu.

**Perde arkasında.** Bir web adresinin yolu içinde taşınan kimlik bilgisi artık istek kaydedilmeden önce kaldırılıyor; sorgu dizesindekiler için bu zaten hep yapılıyordu.

## 0.3.83

**İndirme Trafiği penceresinin adı artık Ağ ve ikinci bir sekmesi var.** İndirmeler, zaten var olan kayıt defteri: her güncellemenin dosya olarak ne kadar tuttuğu. İstekler ise yeni: DuoUpdater’ın sizin adınıza yaptığı her istek, ne için yapıldığı, hangi uygulamaya ait olduğu ve ne kadar tuttuğu; günlüğü kaydırmak yerine ona soru sorabileceğiniz bir filtre alanıyla birlikte. Üstteki rakamlar tüm zamanların toplamını değil, filtrelediğiniz kısmı yansıtıyor.

**Spotify için güncelleme denetimi artık neredeyse hiç ağ kullanmıyor.** Spotify hiçbir yerde bir sürüm dosyası yayımlamıyor; bu yüzden denetim sürümü iki megabaytlık küçük bir yükleyici dosyasından okuyor — ve günün her saatinde, her seferinde dosyanın tamamını indiriyordu. Artık dosyanın değişip değişmediğini soruyor, değişmediyse indirmeyi atlıyor.

**PDF Expert artık güncellemelerini buluyor ve neyin değiştiğini gösteriyor.** Üreticisinin 2022’de güncellemeyi bıraktığı bir sürüm listesini okuyordu; bu yüzden hangi sürüme sahip olursanız olun kendini güncel sayıyordu. Artık uygulamanın kendi güncelleyicisinin kullandığı listeyi izliyor ve yalnızca en yenisinin değil, geçmiş sürümlerin notlarını da getiriyor.

**UTM önizleme derlemeleri artık kendi güncellemelerini alıyor, tek tıkla yükleniyor ve eşleşen sürüm notlarını gösteriyor.** Bir önizleme kopyası önceden nihai sürüm hattına göre ölçülüyor ve sessizce güncel olduğu söyleniyordu; artık kendi hattını izliyor, o hattın nihai sürümünü aldığında da yeniden nihai sürüm hattına dönüyor.

**Perde arkasında.** Kaydedilen istekler, indirme kayıt defteriyle aynı depoya taşındı; böylece aynı indirmenin iki kaydı artık birbirinden ayrışamaz. Mevcut kayıt defteriniz hiç dokunulmadan aktarılıyor.

## 0.3.82

**On beş uygulama daha güncellemeler için izleniyor ve biri hariç hepsi tek tıkla yükleniyor.** AgentsView, AnythingLLM, Chatbox, ChatGPT Classic, DSH Desktop, FluidVoice, GitHub Copilot, Kun, Meetily, Microsoft 365 Copilot, OpenLogi, OpenSuperWhisper, Paseo, T3 Code — hem alpha hem de nightly hattında — ve Vorssaint. İstisna ChatGPT Classic: sizin için denetleniyor, ancak uygulamayı kendisi güncelleyen bir yükleyiciyle geliyor; bu yüzden onu çalıştırmak size kalıyor.

**Sekiz uygulama artık sizi bir web sayfasına göndermek yerine sürüm notlarını DuoUpdater’ın içinde gösteriyor.** Xcode, Antigravity, Antigravity IDE, AnyDesk, AnythingLLM, Chatbox, Headlamp ve Helium. Bunlardan üçünün zaten sizi gönderebileceği bir yer yoktu: AnyDesk’in sayfası bir bot doğrulamasıyla yanıt veriyor, Helium’un geliştiricileri hiç not sayfası yayımlamıyor, Antigravity IDE’nin ise hiçbir türde bağlantısı yoktu.

**Xcode betaları her betada neyin değiştiğini söylüyor.** Satır önceden bir derleme numarası ve bir bağlantı sunuyordu; artık Apple’ın, kullandığınız beta ve o sürümdeki önceki tüm betalar için yayımladığı notları listeliyor.

## 0.3.81

**Word, Excel, PowerPoint, Outlook ve OneNote artık güncellemelerinin yüklendiğini fark ediyor.** Bu beş uygulama, işinizi çoktan bitirdiğiniz yükleyiciyi yeniden açmayı önerip duruyor ve bir türlü yeniden başlatmayı önermeye geçmiyordu — beklemek ya da yeniden denetlemek bunu çözemezdi.

**Yeniden başlatılmayı bekleyen bir satır, her iki pencerede de kendini yeniden açıklıyor.** Bir uygulama hem üreticisinin yayımladığı sürümün ilerisindeyken hem de yeniden başlatılmayı beklediğinde, düğmenin üstündeki satır bambaşka bir şeyi anlatıyordu; pencere ile menü de Tümünü Güncelle sonrasında yeniden başlatılmayı bekleyen satırlar konusunda farklı şeyler söylüyordu.

**Satır etiketleri Rusçada artık uygulama adını sıkıştırmıyor.** Birkaç etiket de çevrilen tüm dillerde, ilgisiz dizelerden ifade ödünç alıyordu.

**Üreticisinin bir sürüme saat belirtmeden yalnızca tarih koyduğu uygulamalarda sürüm notları artık görünüyor.** Bu sürümler önceden hiçbir yerde iz bırakmıyordu.

**Açmayı reddettiğimiz bir sürüm notları sayfası artık nedenini söylüyor.** Önceden boş kalıyordu; bu da hiç not yayımlamayan bir uygulamayla tıpatıp aynı görünüyordu.

**WeChat DevTools nightly sürüm notları artık boş değil.**

**Perde arkasında.** Sürüm ve yayın tarihi işleme tek bir yerde toplandı; böylece bir derleme numarası asla pazarlama sürümü olarak okunamaz. Sürüm zaman çizelgesi de artık üreticinin hiç vermediği bir saat uydurmuyor.

## 0.3.80

**Başarısız denetimler artık pencerede görünüyor.** Pencere, denetimi başarısız olan bir satır için — ya da yok saydığınız, atladığınız veya App Store, Toolbox ya da TestFlight’ın yönettiği bir satır için — hiçbir şey göstermiyordu; bu da “güncel” ile tıpatıp aynı görünüyordu. İki pencere artık aynı uygulama için aynı şeyi söylüyor ve yeniden deneme düğmesi ikisinde de var.

**Herhangi bir satırdaki “Yeniden Denetle” yalnızca o uygulamayı soruyor.** Ayrıca hangi uygulamaların çalıştığını da yeniden okuyor; bu yüzden yanlış görünen yeşil bir noktayı düzeltmenin hızlı yolu bu.

**Atlama ve yok sayma artık pencerenin sağ tık menüsünden yapılabiliyor.** Her iki satır da işlemi iptal etmek için sağ tıklamanızı söylüyordu, ama pencerenin menüsünde böyle bir şey yoktu.

**Arka plan denetimi artık okuduğunuz sürüm notlarını elinizden almıyor.** Saatlik denetim, daha önce yüklenmiş tüm notları atıyordu; bu yüzden açık bir Sürüm Notları bölmesi yeniden dönen göstergeye dönüyordu. Artık notları yalnızca sizin istediğiniz bir yenileme baştan yüklüyor.

**Yarıda kalan indirmeler, tamamlandı sayılmadan önce denetleniyor.** Dosyanın tamamını yeniden gönderen ya da erken kesilen bir sunucuya körü körüne güveniliyordu; sorun bir adım sonra, bozuk bir arşiv yüzünden başarısız olan bir yükleme olarak ortaya çıkıyordu. Önceden her seferinde başarısız olan, proxy arkasındaki indirmeler artık çalışıyor.

**Bir uygulamayı güncellemek artık diskinizdeki tüm uygulamaları yeniden taramıyor.** Her tıklama, sorduğunuz tek uygulamaya bakmak için tüm uygulamalarınızı iki kez baştan sona tarıyordu.

**Chrome’un sürüm notları artık donamaz.** Google’ın blogundaki sıradan bir görünüm değişikliği onları dakikalarca takılı bırakmaya yetiyordu; artık sayfa nasıl görünürse görünsün hızla yükleniyorlar.

**İndirilmiş bir yükleyici artık atılıp yeniden indirilmiyor.** Bir üretici aynı sürümü iki farklı şekilde yazdığında (`v1.2.3` ve `1.2.3`), bekleyen paket tanınmıyor ve Yeniden Başlat çoktan gerçekleşmiş bir değişimi beklemeye devam edebiliyordu.

**Başarısız bir yönetici yüklemesi artık sizin Vazgeç’e bastığınız sanılmıyor.** Hiçbir hata gösterilmiyordu ve o uygulama, siz satır menüsünden yeniden yönetici erişimi isteyene kadar sessizce tek tıkla güncelleme sunmayı bırakıyordu.

**Yeşil “çalışıyor” noktası artık her uygulamayı fark ediyor.** macOS bazı uygulamaların açılışını ya da kapanışını hiç duyurmuyor; bunların noktası, ilgisiz bir şey onu yenileyene kadar yanlış kalıyordu.

**“Tümünü Güncelle” yenileme sırasında artık bir görünüp bir kaybolmuyor**; yenileme ortasında güncellediğiniz bir uygulamaya da zaten yüklediği güncelleme yeniden sunulmuyor.

**Güncelle’ye bastığınız anda başarısız olan bir denetim**, “yapılacak bir şey yok” diye kaydedilmek yerine artık bunu söylüyor.

**Perde arkasında.** Alışılmadık biçimlerde yazılmış yayın tarihleri doğru okunuyor, sürüm notları sayfalarındaki adres denetimi her eşdeğer yazımı kapsıyor ve rutin kayıt işleri artık Mac’inizde herhangi bir uygulama her açıldığında ya da kapandığında diske dokunmuyor.

## 0.3.79

**Docker’ın işareti artık Docker’ın arka plan sürecini değil, arayüzünü tanımlıyor.** Satırda “yerel” yazıyordu; oysa Docker Desktop bir Electron uygulaması. İşaret uygulamanın paketinden okunuyor ve Docker’ın paketi bir sarmalayıcı: adını verdiği program Go ile yazılmış bir arka plan hizmeti, kendine ait hiçbir çerçeve taşımıyor ve pencereleri çizen asıl uygulama onun bir seviye içinde duruyor. Her şey doğru okunuyordu, ama yanlış dosyadan. DuoUpdater artık iç içe geçmiş uygulamaya bakıyor, ama yalnızca şu durumda: dıştaki paket kendisi hiçbir şey getirmiyorsa ve neyle geliştirildiğini kanıtlayan tam olarak bir tane böyle uygulama barındırıyorsa. Böylece gerçek bir arayüzün yanında gelen bir yardımcı süreç, kimliğini yine de ana uygulamaya ödünç veremiyor. Docker artık Electron 42.5.0 olarak okunuyor ve bu notun yazıldığı makinedeki listede bulunan yüz kırk altı uygulama arasında değişen tek satır bu.

**CleanShot X’in sürüm notları yeniden okunabiliyor — 5.0’ınkiler de dahil.** CleanShot yıllardır yaptığı en büyük sürümü yayımladı ve değişiklik günlüğü sayfasını da onunla birlikte yeniden kurdu: tarih sürüm numarasının üstüne taşındı, çevresinde iki yeni katman belirdi ve bir özellik sürümü artık sürüm numarasıyla değişiklik listesi arasına bir giriş yazısı ve iki video bağlantısı koyuyor. DuoUpdater’ın kullandığı okuyucu bunların hiçbiriyle eşleşmez oldu. Durumu boş bir bölmeden daha da kötü yapan şey, bölmenin boş görünmemesiydi: önceki sürüm için zaten kaydedilmiş notlar yeni sürümün başlığı altında ekranda kaldı; böylece bölme 4.8.10’un değişikliklerinin üstünde “5.0” diyordu ve hiçbir yerde aksi söylenmiyordu.

**Bir sürüm yayımlanmadan önce kaydedilen notlar, artık sonsuza dek doğru kabul edilmek yerine yeniden okunuyor.** Bu, aynı hikâyenin diğer yarısı. DuoUpdater, CleanShot 5.0’da neler olduğunu yayımlamadan altı dakika önce 5.0’ın var olduğunu biliyordu; sayfayı o anki haliyle kaydetti ve 5.0’ın altına koydu — ve o andan itibaren her denetim zaten kaydedilmiş bir şey buldu ve bir daha hiç bakmadı. Kaydedilen notlar artık kesin sayılmadan önce oturum başına bir kez üreticiyle karşılaştırılarak doğrulanıyor; böylece notları geç gelen bir sürüm, yanlış kalmak yerine bir sonraki ziyarette kendiliğinden tamamlanıyor.

**Menü çubuğundan açtığınız her şey artık ilk tıklamada açılıyor.** Bir satırda Değişiklik Günlüğü’nü — ya da Ayarlar’ı veya Sürüm Günlüğü’nü — seçmek ilk seferde hiçbir şey yapmıyor, ancak ikinci tıklamadan itibaren çalışıyordu. Menüyü yeniden açmak her denemeyi yine ilk deneme yapıyordu; bu yüzden menüyü açıp bir kez tıklayan ve bir pencere bekleyen kişiler için hiç çalışmıyordu. Menü içindeki ilk tıklama, hedeflendiği işi yapmak yerine DuoUpdater’ı öne getirmeye harcanıyordu. Açılan pencere de artık önde tutuluyor: aynı anda hem öne alınıp hem de yeniden arkaya itiliyordu; bu da tıklamanın hiçbir şey yapmamış gibi görünmesinin diğer nedeniydi.

## 0.3.78

**Kendi adını boş bırakan bir uygulama artık yine de bir ad alıyor.** Eudic (欧路词典) listede bir simge ve bir sürümle duruyordu, ama adın olması gereken yerde hiçbir şey yoktu. Paketi bir görünen ad bildiriyor — ve onu boş bırakıyor, çünkü gerçek adlar uygulamanın çevirilerinde duruyor — DuoUpdater ise bir sonraki soruyu sormak yerine bu boş yanıtı geçerli yanıt kabul ediyordu. Artık uygulamanın diğer adına, ondan sonra da uygulama dosyasının adına başvuruyor; böylece hiçbir satır adsız kalmıyor. Buradaki yüz elli uygulamadan yalnızca biri etkilenmişti; asıl mesele, bilginin zaten orada olması ve es geçilmesiydi.

**Yeniden Başlat, uygulama çıkmayı reddettiğinde artık hiçbir şey yapmayan bir tıklama gibi görünmek yerine bunu size söylüyor.** Bir uygulamanın sizi bekleyen bir penceresi varsa — bir kaydetme istemi, bir oturum açma sayfası, herhangi bir iletişim kutusu — macOS onun çıkmasına izin vermez ve bu taraftan yapılabilecek hiçbir şey yoktur: o pencere uygulamaya aittir. DuoUpdater önceden otuz saniye boyunca dönüp aynı düğmeyi hiçbir açıklama yapmadan geri koyuyordu; bu tam olarak bozuk bir düğme gibi görünüyordu ve insanlar yeniden basıyordu. Satır artık ne olduğunu söylüyor ve o pencereyle ilgilenmeniz için sizi uygulamaya yönlendiriyor. Hiçbir şey değişmedi ve yeni sürüm zaten yüklü; yani geriye gerçekten yalnızca yeniden başlatma kalıyor — üstelik önümüzdeki on dakika içinde uygulamadan kendiniz çıkarsanız, DuoUpdater bunu fark ediyor ve siz hiçbir şeye tıklamadan uygulamayı yeni sürümüyle yeniden açıyor.

**欧路词典 uygulamasının sürüm notları yeniden on altı yıllık bir tarihçe değil, tek bir sürümü kapsıyor.** Uygulama tüm geçmişini — 2.5.0’a kadar her sürümü — en yeni sürümün notlarının içinde yayımlıyor; bu yüzden ayrıntı bölmesi hepsini “26.9.0” başlığı altında gösteriyor ve az önce neyin değiştiğini bulmak için on yılı kaydırarak geçmeniz gerekiyordu. Artık her sürüm, diğer tüm uygulamalarda olduğu gibi listede kendi kaydını alıyor.

**Bir uygulamanın neyle geliştirildiğini gösteren işaret artık Tauri için benzerlik değil, kanıt istiyor.** Tauri pakette bulunabilecek hiçbir iz bırakmıyor — ne bir çerçeve ne de kendine ait bir klasör — bu yüzden bu tek işaret, uygulamanın nasıl paketlendiğinden ve Apple’ın web görünümüne bağlanmasından çıkarılıyordu. Longbridge bunların hepsine uyuyor ama Tauri değil: kendi pencerelerini Zed’in kullandığı çizim motoruyla çiziyor ve arayüzünün bir köşesi için bir web görünümü gömüyor. DuoUpdater artık Tauri demeden önce Tauri’nin kendi parmak izini ikili dosyadan okuyor; böylece bir uygulamaya ancak gerçekten Tauri ise Tauri deniyor — Longbridge de olduğu gibi yerel bir Mac uygulaması olarak görünüyor.

**CapCut, ByteDance’in sunucuları yarım saniyelik kötü bir an yaşadı diye artık kırmızıya dönmüyor.** DuoUpdater’ın CapCut’ın sürümünü sorduğu uç nokta başarı koduyla yanıt veriyor, ama kabaca elli seferde bir, yanıtın yerine bir hata nesnesi gönderiyor — ByteDance’in kendi altyapısındaki dahili bir zaman aşımı; 436 kilobayt beklenirken yaklaşık 390 bayt. Bu taraftaki hiçbir şey bunu CapCut’ın yanıtının biçimini değiştirmesinden ayırt edemiyordu; bu yüzden satır denetimin başarısız olduğunu söylüyordu. Bu da bir sonraki denemede kendiliğinden düzelen bir şey için “bu bozuk, birinin düzeltmesi gerek” anlamına geliyordu. Bu özel biçim artık ne olduğuyla tanınıyor: istek hemen yeniden deneniyor ve ancak beş gün boyunca tekrarlanırsa gerçek bir sorun olarak bildiriliyor.

## 0.3.77

**Listedeki her uygulama artık neyle geliştirildiğini söylüyor.** Bir App Store uygulamasının satırı her zaman mağazanın rozetini taşırdı, diğer tüm satırlar ise birbirine benziyordu — bir Sparkle uygulaması, bir Electron uygulaması ve yerel bir uygulama ayırt edilemiyordu. Artık her adın yanında o teknolojinin kendi işareti var; bir sözcük ve bir cümlelik açıklama için tıklayın ya da ipucu için imleci üzerine getirin: Electron, Tauri, Flutter, Qt, Java, Chromium, Mac Catalyst, Apple Silicon’da çalışan bir iPhone uygulaması ya da yerel bir Mac uygulaması. Çalışma ortamının sürümü de, kesin olarak okunabildiği yerlerde yanında yer alıyor (Electron 42.4.1, Qt 6.2, bir uygulamanın gömdüğü Chromium, geliştirildiği Tauri). Bu bilgi paketin kendisinden okunuyor — bir paketleyicinin eklemek zorunda olduğu çerçeveden, bir başlatıcının ihtiyaç duyduğu çalışma ortamından, ikili dosyanın bağlandığı kitaplıklardan — yani uygulamanın adından yürütülen bir tahmin değil, yüklü olan şey hakkında bir olgu. Uzun bir adın yer bırakmadığı yerlerde simge, adı ikinci satıra itmek yerine kenara çekiliyor: satırın özü addır. Bunların hepsini Ayarlar → Genel’den kapatabilirsiniz.

**LibreOffice artık zaten sahip olduğunuz sürüme bir sürüm düşürmesi olduğunu iddia etmiyor.** İndirme dizini üç parçalı sürümler (`26.8.0`) listeliyor, yüklü kopya ise dört parçalı bir sürüm (`26.8.0.3`) bildiriyor; eksik parçayı sıfırla doldurmak yüklü kopyayı daha yeni gösteriyordu — bu yüzden satır, tam olarak güncel olan bir uygulama hakkında soluk renkli bir “üretici sizden geride” notu gösteriyordu. Uygulamanın bildirdiğinden daha az parça yayımlayan bir kaynak artık daha eski bir sürümü değil, aynı sürümü tanımlıyor sayılıyor; gerçek bir sürüm düşüşü ise yine öyle belirtiliyor.

**Bir güncellemeyle eklenen bir ayar, kendini bir kez gösteriyor.** Ayarlar penceresinin ortasına eklenen yeni bir tercih, kimsenin bulamadığı bir tercihtir. Yeni bir ayar ekleyen bir güncellemeden sonra menü çubuğundaki dişli simgesinde mavi bir nokta beliriyor, ayarın bulunduğu sayfanın kenar çubuğunda da bir tane oluyor, denetimin kendisi de siz ona bakana kadar bir nokta taşıyor. Bu yalnızca gerçekten güncelleyerek bu sürüme gelenler için geçerli — sıfırdan yapılan bir yükleme, yeni tanıştığı uygulamanın doğal bir parçası olan özellikler için noktalarla karşılanmıyor.

## 0.3.76

**Geçen sürümde eklenen Electron manifest uygulamaları artık gerçekten güncellenebiliyor.** 0.3.75, DuoUpdater’a bu uygulamaların içlerinde taşıdıkları dosyayı okumayı öğretti ve DuoUpdater onu okudu da — yeni sürümü, Mac’iniz için doğru indirmeyi ve doğrulama için sağlama toplamını buldu — ama sonra bunların hiçbirini gönderebileceği bir yer yoktu. Yükle düğmesi hiç görünmedi, `duo install` de reddi asıl neden olmayan bir gerekçeyle açıkladı. Yükleme yolu bu sürümde bağlandı. Pratikte hiçbir fark görmeyebilirsiniz: bu okuyucu elle yazılmış tüm kuralların arkasında duruyor, yani yalnızca başka hiçbir şeyin kapsamadığı bir uygulama için devreye giriyor — bu da bugün, bu sürümün derlendiği makinede, hiçbiri değil. Asıl önemi, yarın yükleyeceğiniz ve henüz kimsenin kural yazmadığı uygulama için.

**Sizi yerel bir derlemeden uzaklaştıracak bir indirme artık reddediliyor.** Apple Silicon Intel uygulamalarını çeviri yoluyla hâlâ çalıştırabiliyor; bu da yalnızca Intel’e yönelik bir indirmenin “Mac’inizde çalışır mı?” denetiminden geçip sorunsuz yüklenebilmesi demekti — yerel olarak çalışan bir uygulamanın sessizce çevrilmiş bir kopyasında kalıyor, sonraki her güncellemede de aynı şey yeniden oluyordu. Artık her yerinde yükleme, elinizdekini gelenle karşılaştırıyor ve böyle bir değişimi reddediyor. Ters yönde geçiş ya da evrensel bir derlemeden yalnızca Apple Silicon’a yönelik bir derlemeye geçmek olağandır ve hâlâ serbest.

**Bir indirmenin hangi mimariye ait olduğunu kanıtlayamadığında artık tahmin yürütmek yerine geri çekiliyor.** Bazı üreticiler varsayılan derlemelerinin yanında bir Apple Silicon derlemesi de yayımlıyor ve varsayılanın Intel derlemesi olduğunu anlamanın tek yolu, diğerinin var olduğunu fark etmek. Bu ikinci denetim temiz bir sonuç vermezse — üreticinin sunucusu reddederse, bağlantı koparsa ya da ikisi hangi sürüm olduklarında anlaşamazsa — DuoUpdater artık bu sessizliği yanıt saymıyor. Size sürümü söylüyor ve yükleme sunmuyor; dürüst olan sonuç da bu.

**Bozuk bir kural artık Tanılama’dan kaybolamıyor.** Hem elle yazılmış bir kuralın hem de yeni manifest okuyucusunun kapsadığı uygulamalarda — ki bilinçli olarak çoğu böyle — kuralın başarısızlığı, hemen ardından okuyucunun başarılı olmasıyla siliniyordu; bu yüzden kuralı gerçekten bozulmuş bir uygulama sağlıklı görünmeye devam ediyordu. İkisi artık ayrı kaydediliyor. Manifest okuyucusu da ilk kez kendi başarısızlıklarını bildiriyor; geliştirme makinesindeki üç uygulamanın bir süredir “bulunamadı” yanıtı veren adresleri gösterdiği ortaya çıktı — daha önce hiçbir şey bunu açıkça söylemezdi.

**Güncellemeyi görebilen ama yükleyemeyen satırlar artık iki yerde de aynı şeyi sunuyor.** Menü çubuğunda Finder’ı açan “Aç” etiketli bir düğme vardı, pencerede ise aynı satır için hiçbir şey görünmüyordu.

## 0.3.75

**Electron ile yapılmış uygulamalar artık kimse onları önceden kaydetmeden tanınıyor.** Pek çok Mac uygulaması, içinde güncellemelerinin nerede bulunduğunu söyleyen küçük bir dosya taşır. DuoUpdater şimdiye kadar yalnızca birinin elle kural yazdığı uygulamaları biliyordu — geri kalanların her biri listenizde yanında sürüm numarası olmadan duruyor ve yeni bir derlemenin çıktığını size bildirmenin hiçbir yolu yoktu. Artık bu dosyayı, Sparkle’ınkini her zaman okuduğu gibi doğrudan okuyor; böylece böyle bir uygulama, birinin sonunda ona el attığı gün değil, onu yüklediğiniz gün kapsanıyor.

**Zaten elle yazılmış bir kuralı olan uygulamalara dokunulmuyor.** Yeni okuyucu onların arkasında duruyor; bu yüzden yalnızca bir boşluğu doldurabilir — zaten çalışan bir şeyin yerini asla alamaz.

**Sunulan indirmenin doğru olup olmadığını iki ayrıntı belirliyor ve ikisi de varsayılarak değil, gerçek uygulamalar denetlenerek netleştirildi.** Bazı üreticiler, yanında bir Apple Silicon derlemesi yayımladıkları halde bir Intel derlemesini “birincil” indirme olarak işaretliyor; diğerleri ise Apple Silicon derlemesine Intel derlemesininkinden hiç farklı görünmeyen bir dosya adı veriyor, yani addan hiçbir şey anlaşılmıyor. DuoUpdater mimariye göre seçiyor ve bir indirmenin Mac’inizde çalışacağından emin olamadığı yerde, sorunsuz yüklenip sonra açılmayan bir şeyi size vermek yerine sürümü söylüyor ve yüklemeyi sunmuyor.

## 0.3.74

**Bir uygulamanın beta, sürüm adayı ya da nightly derlemesini kullanıyorsanız, DuoUpdater sessizce yanlış hattı izliyordu.** Hangi hatta olduğunuzu, derlemenizi üreticinin kendi sürüm listesinde bularak belirliyor — ama bir ön sürüm, türediği kararlı sürümle aynı genel sürüm numarasını koruduğunda (ki ön sürümlerde olağan olan budur) onun yerine kararlı kaydı eşleştiriyordu. Etkisi sessizdi: ekranda hiçbir zaman yanlış bir şey görünmüyordu; yalnızca kendi hattınızdaki bir sonraki derlemeden hiç haberiniz olmuyordu ve size gösterilen sürüm notları kararlı hatta aitti. Sorun, Supacode ve TypeWhisper’ın gerçek ön sürüm derlemeleri yüklenip ne olduğu izlenerek bulundu; ikisi de artık gerçekten bulundukları hattı izliyor.

**CapCut’ın betası sizde olmayan bir sürüm gösteriyordu.** Satırda “9.3.4545 → 9.4.0-beta6” yazıyordu; oysa CapCut’ın kendisi, Finder ve diğer tüm güncelleyiciler kopyanızı 9.4.0-beta5 olarak adlandırıyordu. Bazı uygulamalar gerçek sürümlerini çoğu uygulamadan farklı bir alana koyuyor; DuoUpdater da okun sizin tarafında daha derli toplu görünen alanı, üretici tarafında ise gerçek olanı okuyordu. Sunulan güncelleme her zaman doğruydu — yalnızca etiket yanlıştı. Satırın iki yarısı da artık aynı yerden geliyor; hem CapCut için hem de bu şekilde yapılmış diğer yedi uygulama için.

**MacWhisper, GitHub Copilot for Xcode, TypeWhisper ve OpenUsage artık sürüm notlarını gösteriyor.** Dördünün de not paneli boştu: güncelleme akışlarında hiç not yok ve bu, her biri üreticinin gerçekte yayımladıklarıyla karşılaştırılana kadar fark edilmemişti. DuoUpdater artık MacWhisper için uygulamanın kendi sürüm notları sayfasını, Copilot için değişiklik günlüğü dosyasını, TypeWhisper için de değişiklik günlüğü sitesini okuyor; OpenUsage için ise sürüm listesine yönlendiriyor.

**Helium artık kendi güncelleme hizmeti üzerinden güncelleniyor; bu da beta kanalını ve çok daha küçük indirmeleri beraberinde getiriyor.** Uygulama, yalnızca kararlı derlemeleri gösteren herkese açık sürüm listesi üzerinden izleniyordu — bu yüzden Helium betasını kullanan herkese kararlı derleme veriliyordu. Kendi hizmeti yamalar da yayımlıyor; böylece sıradan bir güncelleme, 124 MB’lık yeniden indirme yerine yaklaşık 40 MB tutuyor. Hem kararlı hem de beta derlemesiyle doğrulandı; indirilen dosya, herhangi bir şeyin yerine geçmeden önce yüklü kopyanızın içindeki imzalama anahtarına göre denetleniyor.

## 0.3.73

**Firefox ve Thunderbird için beta, developer ve nightly sürümleri artık düzgün izleniyor — bugüne kadar bu beş hattın hiçbiri tek bir güncelleme bildirmemişti.** Bunlar Mozilla’nın, yalnızca size gösterilen sürümü yayımlayan herkese açık sürüm dosyasından okunuyordu; bir beta yüklendiğinde ise sürümdeki “b5” eki düşüyor: bir Firefox betası tüm döngü boyunca kendini 155.0 olarak tanıtıyor, bu yüzden sorulan tek soru “155.0b5, 155.0’dan daha yeni mi?” oluyordu ve yanıt hayırdı. Nightly daha da kötüydü — Mozilla her gün bir tane yayımlıyor ve hepsinin adı 157.0a1; bu yüzden dört haftalık bir döngü kelimenin tam anlamıyla hiçbir şey üretmiyordu. DuoUpdater artık Mozilla’nın kendi güncelleme hizmetine — Firefox’un yerleşik güncelleyicisinin kullandığı ve uygulamanın kendi içinde adını verdiği adrese — soruyor ve iki tarafın da taşıdığı derleme kimliğini karşılaştırıyor. Yayımlamadan önce beş hattın tamamı gerçek indirmelerle denetlendi: bu hizmetin bildirdiği kimlik, sahip olduğunuz uygulamanın içindekiyle bayt bayt aynı; bir derleme geride olan bir beta artık güncellemesini gösteriyor, aynı gün daha erken derlenmiş bir nightly de öyle. Kararlı ve ESR sürümleri hiç etkilenmemişti ve onlara dokunulmadı. Açıkça belirtmeye değer bir sınır var: bu hizmet yayın tarihi yayımlamıyor; bu yüzden bu beş hat için Sürüm Günlüğü hâlâ Mozilla’nın bir derlemeyi yayımladığı zamanı değil, DuoUpdater’ın onu ilk gördüğü zamanı kaydediyor.

## 0.3.72

**Wispr Flow, AionUi ve Devin artık yalnızca yeni bir sürüm olduğunu söylemekle kalmıyor, tek tıkla güncelleniyor.** Üçü de güncellemelerini zaten görebiliyordu, ama hiçbiri güncelleme uygulayamıyordu. Öne sürülen gerekçe, üreticinin Intel ve Apple silicon için ayrı derlemeler yayımlaması ve DuoUpdater’ın bunlar arasında seçim yapmasının hiçbir yolu olmamasıydı. Varsaymak yerine ölçüldüğünde bu gerekçenin tutmadığı görüldü: Bu üç uygulamanın okunduğu uç noktalar zaten Apple silicon uç noktaları ve DuoUpdater yalnızca Apple silicon’da çalışıyor — yani ortada yapılacak bir seçim hiç yoktu. Her indirme, bağlanmadan önce indirilip denetlendi: içinden doğru uygulama çıkıyor, sizdeki kopyayla aynı geliştirici tarafından imzalanmış ve Apple’ın noter onayından geçmiş; AionUi’ninki ayrıca kendi manifestinin yayımladığı sağlama toplamıyla doğrulandı. Ardından her biri eski bir kopyanın üzerine gerçekten yüklendi ve yeni sürümle açıldı.

**Grok Bot artık izleniyor — yeni sürümler ve tek tıkla güncellemeler.** xAI’ın masaüstü uygulaması, Cursor’ın arkasındaki şirket olan Anysphere tarafından derlenip imzalanıyor ve Cursor’ın kendi sürüm hizmeti üzerinden güncelleniyor. Olağan yolların hiçbirinin bu uygulama için yanıt vermemesinin nedeni de bu: Sparkle akışı yok, App Store kaydı yok, herkese açık bir sürüm deposu yok ve Homebrew cask’i güncelleme işini uygulamanın kendisine geri bırakıyor. DuoUpdater bunun yerine üreticinin kendi sürüm uç noktasını okuyor. Kullanılabilecek iki uç nokta daha vardı ve ikisine de belirli gerekçelerle dokunulmadı: x.ai’daki indirme düğmesinin arkasındaki uç nokta hiçbir sürüm numarası yayımlamıyor; uygulamanın kendi güncelleyicisinin kullandığı ise zaten güncelseniz boş bir gövdeyle yanıt veriyor — bu sessizlik, bozuk bir uç noktadan ayırt edilemezdi. Yükleme, bağlanmadan önce denetlendi: Disk görüntüsü gerçek uygulamayı içeriyor, sizdeki kopyayla aynı geliştirici tarafından imzalanmış ve Apple’ın noter onayından geçmiş. Bilerek sunulmayan tek şey sürüm notları. xAI bu uygulama için hiç sürüm notu yayımlamıyor; yayımladığı tek değişiklik günlüğü ise başka bir ürüne ait.

**Comet ve Msty Studio da artık tek tıkla güncelleniyor; yeni bir denetim de bunu yapabildiği halde yapmayan uygulamaları gözetliyor.** Bu ikisi, güncellemeleri görebilen ama uygulayamayan gruptan geriye kalan son iki uygulamaydı ve ikisinin de yeni bir şeye ihtiyacı olmadığı ortaya çıktı — yalnızca üreticinin gerçekte ne gönderdiğine daha yakından bakmak gerekiyordu. Comet’in indirme bağlantısı imzalı ve bir saat içinde geçerliliğini yitiriyor; bu yüzden güncelleme düğmesi Perplexity’nin kendi ağ geçidine gidiyor ve bağlantı, denetimin çalıştığı saatler öncesinde değil, tıkladığınız anda üretiliyor. Msty dört indirmeyi tek bir dosyada yayımlıyor ve Intel olanı ilk sırada listeliyor; indirmeyi doğrulamak için kullanılan parmak izi de bu ilk girdiden alınıyordu. Parmak izi artık gerçekte indirilen Apple silicon derlemesine bağlı; bu sayede denetimle tıklama arasında yayımlanan bir sürüm de çoğu zaman sessizce yüklenmek yerine yakalanıyor. İkisi de yayımlanmadan önce indirildi ve gerçek yükleme denetimlerinden geçirildi. Asıl ders ise iki uygulamayla da ilgili değildi: DuoUpdater’da, artık geçerliliğini yitirmiş bir gerekçeyle yalnızca algılama modunda bırakılmış bir uygulamayı fark edebilecek hiçbir şey yoktu. Bu yüzden gece çalışan tarif taraması, yalnızca izlediği bir uygulama bize zaten bir yükleyici sunuyorsa artık bunu bildiriyor.

**QQ音乐 artık izleniyor — yeni sürümler, tek tıkla güncellemeler ve sürüm notları pencerede.** Olağan yolların hiçbiri bu uygulama için yanıt vermedi. Ne bir Sparkle akışı ne de Sparkle çerçevesi var; Homebrew cask’i güncelleme işini uygulamanın kendisine bırakıyor; uygulamanın kendi ikili dosyasında adı geçen güncelleme uç noktası ise sorabildiğimiz her şeye 200 ve boş bir gövdeyle yanıt veriyor — bozuk bir uç noktadan ayırt edilemeyen bir sessizlik, bu yüzden ona dokunulmadı. DuoUpdater bunun yerine üreticinin kendi indirme sayfasının beslendiği veri dosyasını okuyor: O sayfa boş bir kabuk olarak geliyor ve içeriğini bu dosyadan dolduruyor; bu dosya aynı zamanda sürüm notlarının bulunduğu tek yer — ne bir blog, ne bir appcast, ne de sürüm başına bir sayfa var. Bu yüzden notlar doğrudan bu dosyadan okunup DuoUpdater’ın kendi penceresinde gösteriliyor; güncelleme de aynı yanıtta adı geçen, noter onaylı disk görüntüsünü yüklüyor. Kayda değer bir tuzak var: Bu dosya, güncel Mac kaydının yanında altı yıllık ikinci bir Mac kaydı da taşıyor; bu yüzden her iki kural da “Mac” sözcüğüne değil, Mac indirmesinin sürüm numarası içeren dosya adına dayanıyor. Açıkça belirtilmesi gereken bir sınır da var: Dosya size gösterilen sürümü yayımlıyor, ama altındaki derleme numarasını hiçbir zaman yayımlamıyor; bu nedenle adı değişmeden yeniden çıkarılan bir sürüm burada görünmez. Olmayan bir güncellemeyi uyduramaz — yalnızca bu tek türü göremez.

**TimeMachineEditor artık izleniyor — yeni sürümler ve tek tıkla güncellemeler.** Olağan yolların hiçbiri bu uygulama için yanıt vermedi: Sparkle akışı yok (uygulamada ne bir akış adresi ne de onu kullanacak çerçeve var), App Store kaydı yok, herkese açık bir sürüm deposu yok ve Homebrew cask’i güncelleme işini uygulamanın kendisine bırakıyor. Buna karşılık küçük bir üretici sitesi var ve oradaki tek indirme bağlantısı sürümü kendi metninde belirtiyor. Homebrew’un kendi sürüm denetiminin dayandığı sayfa da bu ve aynı biçimde okunuyor; yani bu bir tahmin değil, üreticinin bu iş için öngördüğü yol. Güncelleme, düz bir uygulama değişimi olarak değil, üreticinin kendi yükleyici paketiyle yükleniyor ve bu bilinçli bir tercih: İndirme, uygulamanın dışına bir arka plan zamanlayıcısı, bir komut satırı aracı ve bir launch daemon da yerleştiriyor. Yalnızca uygulamayı değiştirmek, yeni kopyayı eskimiş bir zamanlayıcının yanında bırakırdı ve bu uyumsuzluğu fark edecek hiçbir şey olmazdı.

**Little Snitch artık hem kararlı hem de nightly sürümleriyle izleniyor.** Object Development, kendi güncelleyicisinin başka yol kalmadığında başvurduğu bir sürüm dosyası yayımlıyor — Homebrew’un okuduğu dosyanın aynısı — ve DuoUpdater bu dosyayı doğrudan okuyor; çünkü Little Snitch bir Sparkle akışı sunmuyor, cask’i de güncelleme işini uygulamaya bırakıyor. İki sürüm hattı aynı kimliği paylaşıyor ve bu normalde onları birbirinden ayırmayı imkânsız kılar. Ancak bu uygulama kendini sürüm dizesinde ele veriyor: Nightly derleme bu sözcüğü açıkça yazıyor (“6.5 nightly (7301)”), kararlı derleme ise düz bir “6.4.1” olarak görünüyor. Bilerek yapılmayan şeyi de belirtmekte yarar var: Güncellemeyi sizin yerinize yüklemeyecek. Little Snitch, uygulamanın yanında bir sistem uzantısı ve ayrıcalıklı bir arka plan hizmeti çalıştırıyor; yalnızca uygulamayı değiştirmenin bunları sağlam bırakıp bırakmadığı gerçek bir makinede doğrulanmadı. Bu yüzden DuoUpdater, bir ağ filtresi üzerinde tahmin yürütmek yerine yeni sürümün çıktığını söylüyor ve sizi üreticinin kendi indirme sayfasına yönlendiriyor.

**Carbon Copy Cloner artık izleniyor ve sizi ana sürümler arasında taşımaya çalışmayacak.** Bombich aynı anda üç kuşağı birden yaşatıyor — CCC 5, 6 ve 7 — ve hepsi sisteme aynı kimliği bildiriyor. Bu da “daha yeni bir şey var mı?” sorusunu göründüğünden daha çetrefilli hale getiriyor: 7.1.6 gerçekten de 6.1.13’ten büyük sayılıyor, ama aralarında geçiş ayrı bir satın alma gerektiriyor ve CCC 7, bir CCC 5 makinesinde belki hiç yüklü olmayan daha yeni bir macOS istiyor. Yalnızca sürüm numarasına bakarak yanıt vermek, her CCC 5 ve 6 sahibine ücretsiz bir güncellemenin beklediğini sonsuza dek söylerdi ve her seferinde yanılırdı. Bu yüzden DuoUpdater her kuşağı kendi adresinden okuyor ve yalnızca gerçekte sahip olduğunuz kuşak içindeki bir sonraki sürümü sunuyor. CCC içinde beta sürümleri açmış olanlar için betalar da algılanıyor. Şimdilik yalnızca algılama var — CCC, uygulamanın yanına ayrıcalıklı bir yardımcı yüklüyor ve bu, burada zaten sunulan tek tıkla güncellemelerden daha büyük bir iddia olurdu. Bu güncellemeleri daha önce hiçbir şeyin görememesinin nedenini de kayda geçirmekte yarar var: Uygulamanın kendi güncelleme akışı her isteğe başarıyla yanıt veriyor — ama tamamen boş bir sayfayla.

**Mac’inizin gerçekte çalıştıramayacağı bir güncelleme artık indirilip yüklenmiyor.** Her uygulama paketi, açılabileceği en eski macOS sürümünü belirtir; bazı üreticiler en yenisini de belirtir: “Bu derleme o kadar yeni bir işletim sistemi için değil.” macOS 27’ye henüz ayak uyduramamış bir uygulama bunu böyle söyler. DuoUpdater ikisini de okumuyordu. Sparkle akışıyla izlenen uygulamalarda alt sınıra zaten uyuluyordu, ama bunlar azınlıkta: Tipik bir Mac’teki uygulamaların büyük bölümü üreticinin kendi uç noktasından ya da GitHub sürümlerinden okunuyor ve bir GitHub sürümü hiçbir yerde macOS gereksinimi yayımlamıyor. Bu nedenle sizinkinden daha yeni bir macOS’a geçmiş bir uygulama size sunulabiliyor, eksiksiz indirilip yerine konabiliyor — ve sonra açılmıyordu. DuoUpdater artık bu gereksinimi, işlemcinize uygun derlenip derlenmediğine bakan mevcut denetimin hemen yanında, indirilen uygulamanın kendisinden okuyor ve çalışan bir kopyayı açılmayacak bir kopyayla değiştirmek yerine değişimi reddediyor. Bir akışın yayımladığı durumlarda üreticinin belirttiği üst sınıra da uyuluyor; böylece geliştiricinin sizin macOS sürümünüz için olmadığını işaretlediği bir derleme en baştan sunulmuyor. Açıkça belirtilmesi gereken üç sınır var. Gereksinimi indirilen dosyadan okumak, indirmenin çoktan gerçekleşmiş olması demek — bu, trafiği değil bozuk bir yüklemeyi önlüyor, çünkü çoğu uygulama için daha önce sorulabilecek bir yer yok. En yeni sürümünü Mac’inizin çalıştıramadığı bir uygulama o güncellemeyi göstermeye ve yüklemeyi reddetmeye devam edecek; ret mesajı artık istenen macOS sürümünü belirtiyor, ancak DuoUpdater bu yanıtı henüz hatırlayıp güncellemeyi sunmayı bırakmıyor. Son olarak denetim, DuoUpdater’ın uygulama paketini kendisinin değiştirdiği yolları kapsıyor: Bir yükleyici paketi dosyayı macOS’a teslim eder ve macOS paketin kendi gereksinimlerini uygular; Homebrew ile App Store ise kendi derlemelerini kendileri seçer. App Store’un iPhone ve iPad bölümünden gelen uygulamalar bilerek atlanıyor, çünkü belirttikleri sürüm bir iOS sürümü ve bunu macOS ile karşılaştırmak hiç denetlememekten daha kötü olurdu. Henüz açıkça söylenmeyen bir şey de var: Geliştiricinin bir derlemeyi sizin macOS sürümünüz için olmadığını işaretlediği durumlarda o güncelleme basitçe sunulmuyor ve uygulama, nedenini açıklamak yerine güncel görünüyor. Eski bir Mac’te bu sorun, macOS’u yükselttiğiniz gün kendiliğinden çözülür. Fazla yeni bir Mac’te ise çözülmez ve orada sessizlikten daha iyi bir yanıt borçluyuz.

## 0.3.71

**百度网盘 artık izleniyor — yeni sürümler, tek tıkla güncellemeler ve sürüm notları pencerede.** Olağan yolların hiçbiri açık değildi. Sparkle akışı yayımlamıyor; Homebrew cask’i elle yüklenmiş bir kopya adına konuşamıyor; uygulamanın kendi paketinde adı geçen güncelleme manifesti de artık ölü — o dosya, arm64 ikizi ve hepsini barındıran dizin 404 yanıtı veriyor. Bu yüzden DuoUpdater, üreticinin kendi indirme sayfasının beslendiği uç noktayı okuyor ve aynı yanıtta adı geçen, noter onaylı arm64 disk görüntüsünü yüklüyor. Sürüm notları da aynı yoldan geliyor: “版本更新” sayfasında bir Mac版 sekmesi var, ancak sayfanın kendisi boş geliyor ve içeriğini bir API’den dolduruyor; bu yüzden DuoUpdater o API’yi doğrudan okuyor ve son kırk sürümü kendi penceresinde gösteriyor. Açıkça belirtilmesi gereken bir sınır var: Bu akış size gösterilen sürümü yayımlıyor, ama altındaki derleme numarasını hiçbir zaman yayımlamıyor; bu nedenle adı değişmeden yeniden çıkarılan bir sürüm burada görünmez. Olmayan bir güncellemeyi uyduramaz — yalnızca bu tek türü göremez.

**Başarısız olan bir denetim artık boş bir yer göstermek yerine başarısız olduğunu söylüyor.** Sürümünü yalnızca üreticinin kendi uç noktasının yanıtlayabildiği bir uygulamanın “yanıt yok” demenin tek bir yolu vardı: boş bir tire. Bu da hiçbir şeyin kapsamadığı bir uygulamanın görünümüyle aynıydı. Bu yüzden bir üretici uç noktasının zaman aşımına uğraması ya da taşınması, tam olarak “DuoUpdater bu uygulamayı izlemiyor” gibi okunuyordu — kalıcı görünen bir hüküm; ne bir Yeniden Dene seçeneği vardı ne de “uygulama denetlenemedi” sayısında bir yer. Bunlar artık gerçekte oldukları şey olarak, yani başarısız bir denetim olarak görünüyor: bir Yeniden Dene düğmesi, sayımda bir yer ve adı konmuş bir neden. Bilerek her şey değil: Mac’inizin hiçbir şey yapamayacağı bir durum — bulunduğunuz sürüm hattı için bir tarif olmaması ya da bu makinede olmayan bir kimlik isteyen bir uç nokta — her zamanki sessiz tire olarak kalıyor; üst üste üç tur başarısız olan bir denetim de afişi sonsuza dek meşgul etmek yerine yine afişten çekiliyor. JetBrains Toolbox’ın yüklediği bir uygulama da arkasındaki sürüm okunamadığında “Toolbox’ı Aç” düğmesini koruyor, çünkü her iki durumda da yapılacak şey Toolbox’ı açmaktı.

**“Uygulamak için yeniden başlatın” hatırlatması artık yeniden başlattığınızda kayboluyor.** Bir uygulamanın kendi güncelleyicisi arka planda bir derleme indirdiğinde DuoUpdater bunu size bildiriyor ve bildirimde bir Yeniden Başlat düğmesi sunuyordu. Düğme işe yarıyordu — uygulama yeni derlemeyle geri geliyor ve “Şimdi 1.0 sürümü çalışıyor.” diyordu — ama yerini aldığı hatırlatma Bildirim Merkezi’nde altta kalıyor ve az önce yeniden başlattığınız bir şeyi yeniden başlatmanızı istemeyi sürdürüyordu. DuoUpdater hatırlatmanın geçerliliğini *yitirmesini* bekliyordu ve denetim yaptığı an, tam da zaten hesaba katılmış olan tek andı. Artık bekleyen bir yeniden başlatma olmadığı her durumda hatırlatmayı kaldırıyor; bu, DuoUpdater çalışmıyorken kendi güncellemesini uygulamış bir uygulamanın geride bıraktığı hatırlatmayı da temizliyor.

## 0.3.70

**Tek bir sürüm numarası altında çok sayıda derleme yayımlayan uygulamalar artık her yerde doğru ele alınıyor.** Bir Mac uygulaması iki sürüm dizesi taşır: size gösterdiği sürüm (“1.0”) ve gerçekten artan bir derleme numarası. Çoğu uygulama ikisini birlikte ilerletir. Bazıları yalnızca derlemeyi ilerletir: Amp tek bir günde on derleme yayımladı ve hepsinin adı 1.0’dı; Surge dört ayrı sürümü 6.9.0 adıyla çıkardı; JetBrains’in önizleme derlemeleri de aynısını yapıyor. DuoUpdater “bu değişti mi?” sorusuna yaklaşık bir düzine yerde *gösterilen* sürümü karşılaştırarak karar veriyordu; bu uygulamalar için o karşılaştırma, gerçekte ne olmuş olursa olsun, yalnızca “hayır” — ya da “bunlar aynı mı?” diye sorulan yerlerde “evet” — yanıtını verebiliyordu. Aşağıda bunun neleri bozduğu anlatılıyor. Hepsi tek bir hata; Amp onu görünür kıldığı için bulundu.

**Yeniden Başlat artık üç dakika boyunca takılmış gibi görünüp ardından yaşanmamış bir hatayı bildirmiyor.** Kendi güncelleyicisinde bekleyen bir derleme bulunan bir uygulamada Yeniden Başlat’a tıklamak, üç dakika boyunca dönen bir gösterge çıkarıyor ve ardından işlemin başarısız olduğunu söylüyordu — oysa güncelleme bir iki saniye içinde uygulanmış ve uygulama çoktan yeni derlemeyle yeniden açılmıştı. DuoUpdater, gösterilen sürümde hiçbir zaman gelmeyecek bir değişikliği bekliyordu. Amp’te ölçüldü: bir saniyeden kısa süren bir değişim için 189 saniye dönen gösterge. Artık bir saniyeden çok daha kısa sürede sonuçlanıyor ve gerçek bir hata yine hata olarak bildiriliyor.

**Yeniden Başlat artık size çoktan eskimiş bir derleme sunmuyor.** Bir uygulamanın güncelleyicisi bir derlemeyi indirmiş ve geliştirici o arada bir başkasını yayımlamışsa DuoUpdater yine de Yeniden Başlat’ı sunuyordu — böylece yeniden başlatıyor ve anında bir derleme geride kalıyordunuz; oysa o denetim tam da bunu önlemek için yazılmıştı. Bu satırlar artık onun yerine güncel derlemeyi indiren **Güncelle** düğmesini sunuyor.

**Bir sürümü atlamak artık bir uygulamayı sonsuza dek susturmuyor.** Bilinmesi gereken asıl madde bu. “Bu sürümü atla”, tek bir sürümü reddedip bir sonrakinin gelmesine izin vermek için var. Ancak yalnızca gösterilen sürümü kaydediyordu; bu yüzden derlemeler boyunca tek bir sürüm adını koruyan bir uygulamada bir kez atlamak, gelecekteki *her* sürümü reddediyordu — kalıcı olarak, yeniden başlatmalardan sonra da süren biçimde ve uygulamanın sessizleştiğini gösteren hiçbir şey ekranda belirmeden. Atlama artık reddettiği derlemeyi kaydediyor. Onarımın bir sonucu var: DuoUpdater’ın önceki bir sürümüyle atlanmış bir sürüm size bir kez daha sunulacak, çünkü eski kayıt hangi derlemeyi kastettiğini söyleyemiyor. Onu yeniden atlarsanız bu kez doğru kaydediliyor.

**Hiçbir şey değiştirmemiş gibi görünen güncellemeler için geri alma yeniden görünüyor.** Çalışma alanı, hiçbir şey yapmayacak bir geri almayı gizler — ve bu uygulamalarda her geri alma hiçbir şey yapmayacakmış gibi görünüyordu. Bu yüzden gerçek bir güncellemeden sonra satır kayboluyor, diskte eksiksiz bir yedek dururken ona ulaşmanın hiçbir yolu kalmıyordu.

**Yeniden başlatma hatırlatması yine her derleme için bir kez duyuruluyor ve geliştiricinin bir derleme daha yayımlamasına da dayanıyor.** 0.3.69, her beş dakikada bir tekrarlanan bir hatırlatmayı, hazırlanan her derleme için yalnızca bir kez konuşan bir hatırlatmayla değiştirmişti — ama derlemeyi adıyla tanımlıyordu; bu yüzden bu uygulamalarda ilkini duyurup sonraki her birinde sessiz kalıyordu. Bu düzeltildi. Ayrıca: Bir uygulama kaydedilmemiş işi olduğu için kapanmayı reddederse DuoUpdater, siz yanıt verdikten sonra onu yeniden açmak üzere bir not tutar. Siz karar verirken geliştirici başka bir derleme yayımlarsa bu not eskiden atılıyordu; uygulama değişimden sonra kapalı kalıyor ve onu yeniden açacak hiçbir şey olmuyordu. Not artık yeni derlemeyi izliyor.

**Başarısız bir App Store güncellemesi artık sessizce başarılı olarak kaydedilmiyor**, indirilmiş bir yükleyici paketi de daha eski bir derlemeyse artık şu an sunulan paket gibi değerlendirilmiyor. İkisi de aynı karşılaştırmadan kaynaklanıyordu. Sürüm geçmişi de bir uygulamanın on derlemesini tek bir sürüm olarak sayıyordu; bundan sonra bunları ayrı ayrı sayıyor, ancak zaten kaydedilmiş geçmiş geri kazanılamıyor.

**Bir yeniden başlatmanın hangi derlemeyi uygulayacağını artık satırın kendisi söylüyor.** Satırda “1.0 → 1.0” yazıyordu — hiçbir fark belirtmeyen bir satır. Artık “1.0 (129) → 1.0 (130)” yazıyor, ama yalnızca değişen şey derleme olduğunda; sürüm adlarının zaten farklı olduğu yerlerde satır değişmiyor. Aynı düzeltme Yeniden Başlat ipuçlarına, bildirime, bir yüklemenin neden ertelendiğini açıklayan nota ve `duo install` komutunun ret mesajına da uygulanıyor.

## 0.3.69

**微信输入法 ve 豆包输入法 yeniden tek tıkla güncellenebiliyor — üstelik kendilerini güncelledikleri yöntemle.** Giriş yöntemleri için tek tıkla güncelleme, bir kullanıcının giriş yöntemi ayarları kaybolduktan sonra 0.3.25’te, yayımlandığı gün geri çekilmişti. Sorun yüklemenin biçimindeydi: İlk kez yükleme yapan bir yükleyici gibi uygulamanın tamamını değiştiriyordu. Bir giriş yöntemi macOS’a uygulamasının *konumuyla* kaydedilir ve bu iki uygulama da kendilerini o konuma dokunmadan günceller — uygulamayı yerinde tutup içindekileri değiştirirler. DuoUpdater artık aynısını yapıyor; böylece kayıtlı uygulama güncellemeden aynı uygulama olarak çıkıyor ve herhangi bir noktadaki bir hata, çalıştırdığınız kopyayı olduğu yerde bırakıyor. Üstelik ikisi de artık parolanızı sormuyor.

**İkisinden biri güncellenmeden önce öğrendiği her şey kopyalanıyor.** Sözlüğünüz, ayarlarınız ve hesap durumunuz uygulamanın içinde durmuyor; bu yüzden DuoUpdater’ın zaten tuttuğu geri alma kopyası bunları kapsayamıyordu. Artık her giriş yöntemi güncellemesinden önce bunların anlık görüntüsü alınıyor ve geri almayla birlikte geri yükleniyor; kopyalamanın maliyeti de neredeyse sıfır — birinin 578 MB’lık verisini kopyalamak saniyenin onda biri kadar sürüyor ve neredeyse hiç disk alanı kaplamıyor. Bu bir onarım değil, bir güvenlik ağı: Bir uygulamanın bir sonraki açılışında verilerinizle ne yapmaya karar verdiği, uygulamanın kendi kodunun işidir ve hiçbir şey bunun önüne geçemez. Ama artık dönülebilecek bir yer var.

**Bir güncelleme artık bir uygulamanın kendini güncelleme yeteneğini sessizce elinden almıyor.** DuoUpdater bir uygulamayı değiştirmek için yöneticiye ihtiyaç duyduğunda uygulamanın sahibini geri yüklüyor, ancak uygulamanın yüklenirken aldığı izinleri geri yüklemiyordu — oysa bir indirme normalde bir yükleyicinin ayarladığından daha dar izinlerle açılır. İki giriş yöntemi için bu, kendi güncelleyicilerinin bir sonraki güncellemeyi tamamlayabilmesi ile arkasını toplayamaması arasındaki fark demek. Bir uygulamanın yüklenirken aldığı izinler artık onun yerini alan kopyaya da aktarılıyor.

**DuoUpdater artık aynı uygulamayı her beş dakikada bir yeniden başlatmanızı istemiyor.** Kendini güncelleyen bir uygulama yeni sürümü diske bırakır ve siz onu kapatana kadar bekler. DuoUpdater bunu her denetimde fark ediyor ve her seferinde bir hatırlatma gönderiyordu; böylece henüz yeniden başlatmamaya karar verdiğiniz bir derleme, siz onu öyle bıraktığınız sürece sizi rahatsız etmeyi sürdürüyordu. Artık her derleme bir kez duyuruluyor: Yeniden başlatın, atlayın ya da uygulamayı yok sayın, sessiz kalıyor; sonraki derleme ise kendini normal şekilde duyuruyor.

**Yeniden başlatılmayı bekleyen bir uygulama artık güncelleme olarak sayılıyor, yok sayılan bir uygulama ise hiç sayılmıyor.** Diskte zaten duran yeni bir sürüm *bir güncellemedir* — yalnızca erken indirilmiştir; bu yüzden artık yanlarında ayrı bir sayım olarak değil, simgedeki işarette ve “N güncelleme var” satırında sayılıyor. Yok sayılan uygulamalarda durum tersiydi: Yok saydığınız bir uygulama simgedeki işareti yakabiliyordu, oysa satırında soluk bir “Yok sayıldı” etiketi vardı ve basılacak bir düğme yoktu; yani sayı, üzerinde işlem yapamayacağınız bir şeyi gösteriyordu. Yok saymak ve atlamak artık üç yerin hepsinde aynı anlama geliyor: hatırlatmada, simgedeki işarette ve listede.

**搜狗输入法 artık izleniyor — web sitesini okuyarak değil, kendi güncelleyicisine sorarak.** Sogou’nun değişiklik günlüğü sayfası üç bölümlü sürüm numaraları yayımlıyor, yüklü kopya ise dört bölümlü bir numara taşıyor; bu yüzden sayfayla karşılaştırmak, önce gerçek sürümü kırpmak anlamına gelirdi. Uygulamanın kendi güncelleme denetimi ise paketin kendi numaralandırmasıyla yanıt veriyor. DuoUpdater bu uç noktaya uygulamanın sorduğu şekilde soruyor ve sürümü dört bölümüyle birlikte buradan okuyor; böylece yalnızca son bölümü değişen bir yeniden derleme de görülebiliyor. Bu uygulama için yalnızca algılama var: Sogou’nun güncelleyicisi uygulamayı değiştirmekten çok daha fazlasını yapıyor — bir QuickLook oluşturucusunu yeniden kaydediyor, verilerinizi yeni bir konuma taşıyor ve giriş yöntemini zorla kapatıyor — bu yüzden güncellemenin kendisi ona bırakılıyor. Bilinmesi gereken bir şey daha var ve bu bizim değil, Sogou’nun işi: Uç noktaları, soran macOS sürümüne göre yanıt veriyor ve macOS 28’deki bir Mac kendisi için sorduğunda 2023’ten kalma bir derleme alıyor. DuoUpdater kendi adına sormuyor; bu yüzden size gösterilen sürüm her Mac’te güncel olan sürüm.

**Sonradan gelen bir düzeltmenin doğru çıkaracağı sürüm notları artık kalıcı olarak yanlış kalmak yerine yeniden okunuyor.** Notlar, yayımlanmış bir sürümün notlarının hiç değişmeyeceği varsayımıyla sürüm başına önbelleğe alınıyor. Bu, notların kendisi için doğru, ama DuoUpdater’ın onlardan çıkarabildikleri için değil; bu yüzden notları bozuk çıkan bir uygulama, sonradan kaç ayrıştırma düzeltmesi yayımlanırsa yayımlansın, o sürüm için öyle kalıyordu. Artık önbellekteki her kayıt, onu çıkarma mantığının hangi kuşağının yazdığını da saklıyor ve daha eski bir kuşağın yazdığı kayıt yeniden indiriliyor. Her iki önbellek de bunu yapıyor: uygulama değişiklik günlükleri ve Homebrew formül notları.

**Bir CDN’de başarısız olan bir denetim, bozuk sayılmadan önce bir kez daha deneniyor.** 502, 503 ve 504’ün hepsi, aradaki bir sunucunun arkasındaki asıl sunucuya ulaşamadığı anlamına gelir: İstek hiç ulaşmamıştır, bu yüzden aynı istek bir an sonra genellikle başarılı olur. Headlamp’in denetimi tam da bu yüzden çöktü — GitHub hiçbir hız sınırı başlığı olmadan 504 yanıtı verdi. Bu üç kod artık saniyenin onda sekizi kadar bekledikten sonra bir kez yeniden deneniyor. Bilerek yalnızca bu üçü: 500, sunucunun kendisinin başarısız olduğu anlamına gelir ve tekrarlamak çoğunlukla hatayı yeniden üretir; hız sınırına takılan bir isteği yeniden denemek ise tam da şikâyet edilen kotayı harcar.

**Bir Homebrew formülünün sürüm notları artık ait oldukları sürümü izliyor.** Notlar sürüm başına değil formül başına hatırlanıyordu; bu yüzden bir formülün notları bir kez yüklendikten sonra, oturum boyunca ona her bakışta — daha yeni bir sürüm çıktıktan sonra bile — o ilk sürümün notları gösteriliyordu. Notları okumak ayrıca formül listesinin geri kalanının beklediği kuyruğu da meşgul ediyordu; bu yüzden yavaş bir `brew info`, çevresindeki listeyi durdurabiliyordu.

**Çalışma alanının kenar çubuğunda bir uygulamaya sağ tıklayarak onu açabilirsiniz.** Menü çubuğu satırlarının hep sunduğu Aç komutunun aynısı, artık ona ihtiyaç duymanızın daha olası olduğu pencerede.

**İndirilmiş bir yükleyiciyi atmak, geride bıraktığı hatayı da beraberinde götürüyor.** Hazırlanmış bir paketi atmak satırı zaten Güncelle durumuna döndürüyordu, ama az önce vazgeçtiğiniz denemeden kalan kırmızı hata mesajı satırda duruyordu — ve onu hiçbir şey temizlemeyecekti, çünkü bir hata ancak satır güncel duruma geçtiğinde kaldırılır; hâlâ güncelleme sunan bir satır ise bu duruma hiçbir zaman geçmez. Artık hata da indirmeyle birlikte gidiyor.

**İsteğe bağlı komut satırı yardımcısı `duo` artık kendini yanlış tanımlamıyor.** `--timeout` kaldırıldı — kabul ediliyor ve belgeleniyordu, ama hiçbir şey onu okumuyordu. `--budget` ilk kez belgelendi ve ondan söz eden tek mesaj artık her zaman “15” yerine gerçek bir dakika sayısı veriyor. `--max-calls` varsayılan değerinin 20 olduğunu iddia ediyordu, oysa 6. Sayı bekleyen bir seçeneğe sayı olmayan bir değer verilmesi artık hata: `duo verify --max-concurrency 1x` eskiden yok sayılıyor ve tarama varsayılan değer olan dörtle yapılıyordu; bir taramayı bilerek yavaşlatmak isteyen biri için bu tam ters bir sonuç. Ayrıca `duo verify` artık gerçekten yaptığı istekleri sayıyor: 502 yanıtı verip yeniden denemede başarılı olan bir akış, sessizce iki kez sorulmuşken artık temiz bir `ok` bildirmiyor. `-h`, `--help`’in çalıştığı her yerde çalışıyor.

## 0.3.68

**Dört uygulama daha izleniyor, iki sürüm kanalı daha eklendi ve hepsi yerinde güncelleniyor.** CapCut, Canva ve yayımlandığı iki sitenin ikisinde de WorkBuddy — uluslararası site ile Çin sitesi birbirinden bağımsız sürüm hatları işletiyor, bu yüzden yüklü bir kopyaya yalnızca kendi sitesine ait sürüm ve notlar sunuluyor. Termius ve VSCodium, zaten kapsanan kararlı derlemelerin yanına Beta ve Insiders kanallarını ekliyor. CapCut’ın ikinci hattı işin zor kısmı: CapCut’ın kendi içindeki bir anahtarla seçiliyor ve sürüm numarasında hiçbir yerde görünmüyor; bu yüzden hangi hatta olduğunuz, o anda çalıştırdığınız derlemeden tahmin edilmek yerine diskteki kopyadan okunuyor. O kutuyu işaretlerseniz bilmeniz gereken bir şey var: DuoUpdater size en yeni betayı çıktığı anda sunacak; bu da CapCut’ın kendi kademeli dağıtımının size ulaşacağı noktanın ilerisinde olabilir.

**Android Studio’nun önizleme kanalları artık size elinizdekinden daha eski bir derleme sunmuyor.** Google sürümlerini sürüm numarasına göre değil, yayımlandıkları sıraya göre listeliyor; DuoUpdater da bu listede üç ayrı arama yapıyordu — bir kez sürüm, bir kez tarih, bir kez de indirme için. Bu yüzden daha yeni bir canary’den sonra yayımlanan bir sürüm adayı, sürümü bir girdiden, dosyayı başka bir girdiden sağlayabiliyordu. 26 Ağustos’ta Canary kanalı, 2026.2.1 Canary 2 çoktan yayımlanmışken 2026.1.4 RC 2 yanıtını verdi. Bu yanıtların her biri artık aynı girdiden gelmek zorunda.

**Yeniden derlenen bir sürüm artık yerini alması gereken kopyayı yüklemiyor.** Bir proje bir sürümü sürüm numarasını değiştirmeden yeniden derlediğinde iki dosya da aynı etiketin altında kalır — KeePassXC, orijinal `KeePassXC-2.7.11-arm64.dmg` dosyasının yanında `KeePassXC-2.7.11-1-arm64.dmg` dosyasını yayımlıyor — ve DuoUpdater hangisi önce listelenmişse onu alıyordu. Bu sıra alfabetik; bu kez yeniden derlemeyi tesadüfen başa koymuştu, bir dahaki sefere sona koyacaktı. Bunların hiçbiri görünür değildi: Satırdaki sürüm doğruydu, yalnızca arkasındaki dosya yanlıştı. Doğru dosya artık dosya adının kendisinin söylediğine göre seçiliyor.

**Nightly ve snapshot derlemeleri artık gerçekte oldukları şey, yani yayın öncesi derlemeler olarak tanınıyor.** VLC’nin nightly derlemesi, KeePassXC snapshot’ı ve Freelens nightly, kararlı uygulamanın adı ve paket tanımlayıcısıyla yükleniyor; bu yüzden onları ele veren tek şey sürüm dizeleri — ve bu dize okunmuyordu. Kararlı yükleme olarak sayılıyorlardı; bir nightly derlemeye kendi üzerine yazılacak sıradan bir sürümün sunulması da böyle oluyor. DB Browser for SQLite’ın nightly derlemesi de aynı nedenle uygulamanın kendi dosya adından okunuyor. Orada sorun gerçekti ama gizliydi: Donmuş sürüm numarası, güncel kararlı sürümün ancak kararlı sürüm ona yetişene kadar üstünde kalıyor; o noktada yüklü her nightly kopyasına sessizce kararlı bir derleme verilmiş olacaktı.

**Bir uygulamayı yeniden başlatmak artık gerçekte ne olduğunu bildiriyor.** Birkaç uygulama kendi paketinin içinde ikinci bir uygulama taşıyor — Surge, Dashboard’unu orada tutuyor — ve yalnızca bu iç uygulamanın yeniden başlatılması gerektiğinde DuoUpdater, hiçbir şey olmamışken dış uygulamanın yeniden başlatıldığını söylüyordu. Artık iç uygulamanın kendi sonucunu bildiriyor ve hiç gerçekleşmemiş bir yeniden başlatma için bildirim göndermiyor.

**İndirmesi tamamlanmış bir güncelleme artık bunu belirtiyor ve ondan vazgeçebiliyorsunuz.** İndirmesi bitmiş bir yükleyici paketini tutan satır, mavi bir Yükle düğmesinden başka bir şey göstermiyordu — indirmenin zaten bittiğini ya da düğmenin güncellemeyi baştan başlatmak yerine yükleyiciyi yeniden açtığını söyleyen hiçbir şey yoktu ve fikrinizi değiştirmenin de bir yolu yoktu. Bu bilgi artık bir ipucunda gizli değil, doğrudan satırda; satırın sağ tıklama menüsündeki **İndirilen Yükleyiciyi Sil** komutu da indirmeyi silip satırı Güncelle durumuna döndürüyor. Aynı uygulamanın bir yüklemesi zaten sürerken birini atmak, indirmesi yeni bitmiş bir paketi de silebiliyordu; artık silemiyor.

**Kaldırılmış sayfalara giden sürüm notu düğmeleri yeniden çalışan sayfaları açıyor.** Microsoft, Edge’in kurumsal sürüm notu sayfalarının adını değiştirdi, Termius da değişiklik günlüğünü taşıdı; bu yüzden üç Edge kanalı ve Termius sizi artık var olmayan bir sayfaya gönderiyordu. Bu sayfaların hâlâ yerinde olup olmadığını hiçbir şey denetlememişti; geri kalan her şey sağlıklı görünürken süresiz olarak bozulabilmelerinin nedeni buydu. Artık düzenli aralıklarla denetleniyorlar. Edge’in Dev kanalına hiç düğme verilmiyor: Microsoft bu kanal için not yayımlamayı bıraktı ve hâlâ var olan her sayfa başka bir sürüm hattına ait.

**Raycast, sürüm 2’ye geçişte izleniyor — ama yalnızca onu çalıştırabilen Mac’lerde.** Raycast 2, macOS Tahoe ve Apple silicon gerektiriyor. Bu koşulları karşılamayan bir Mac sürüm 1 hattında kalıyor ve artık asla yükleyemeyeceği bir sürümden haberdar edilmiyor. İki hat artık sürüm notlarını da ayrı tutuyor; böylece sürüm 1 yüklü bir kopya sürüm 2’nin değil, sürüm 1’in geçmişini görüyor.

**Sürüm notları artık daha fazla uygulama için DuoUpdater’ın kendi penceresinde gösteriliyor.** Üç hattının tamamında BetterDisplay, Shotbase ve iki sitede de WorkBuddy. BetterDisplay’in notları artık indirme düğmesinin ham işaretleme koduyla bitmiyor ve katkıda bulunanlar listesini her sürümde yinelemiyor.

**İsteğe bağlı komut satırı yardımcısı `duo` artık anlamadığı bir komut satırını reddediyor.** Yanlış yazılmış bir seçenek eskiden yok sayılıyordu ve yok sayılan bir seçenek, hiç vermediğiniz bir seçenekle aynı etkiyi yapar — bu yüzden `duo verify --githubb`, istediğiniz tarif yerine sessizce tüm tarifleri denetliyordu. Bilinmeyen seçenekler, değeri verilmemiş bir seçenek ve fazladan argümanlar artık komutun gerçekte neleri kabul ettiğini belirten hatalar veriyor; `--help` de her komuttan sonra çalışıyor.

## 0.3.67

**BetterDisplay’in yayın öncesi ve dahili derlemeleri artık bunları isteyenlere sunuluyor.** BetterDisplay, üç sürüm hattının hepsini tek bir güncelleme akışında taşıyor ve aralarında kendi ayarlarındaki iki anahtarla seçim yapıyor. DuoUpdater hattınızı yalnızca o an çalıştırdığınız derlemeden tahmin edebiliyordu; oysa bu derleme, açtığınız ama henüz sonucunu görmediğiniz bir anahtar hakkında hiçbir şey söylemez. Bu yüzden iki anahtarı da açık olan ve kararlı bir derlemede duran birine güncel olduğu söyleniyordu, oysa BetterDisplay’in kendi güncelleyicisi dört sürüm ileride bir sürüm sunuyordu. Gerçek tercihiniz artık BetterDisplay’den okunuyor; dahili derlemeleri açmanın sıradan yayın öncesi sürümlerin de gelmeye devam etmesini sağladığı durum da buna dahil. Yalnızca Apple silicon’a yönelik önizleme derlemeleri bilerek dışarıda bırakılıyor; böylece bir Intel Mac’e çalıştıramayacağı bir derleme asla sunulmuyor.

**Bir uygulamanın sürüm kanalını art arda iki kez değiştirmek artık satırı eski yanıtta takılı bırakmıyor.** Bir kanal anahtarını değiştirmek, DuoUpdater’ın o uygulamayı yeniden denetlemesini sağlıyor; ilk denetim hâlâ sürerken yapılan ikinci bir değişiklik ise eskiden hesaba katılmıyordu. Satır, az önce betaları kapatmış birine beta sunmayı, ilgisiz bir şey başka bir denetimi tetikleyene kadar sürdürüyordu. Artık yeni değişiklik eskisinin yerini alıyor; yarıda kesilen bir denetim de ulaşamadığı uygulamaları işlenmiş olarak kaydetmek yerine bir sonraki tur için işaretliyor. Satırlar bir değişiklikten sonra denetim durumuna da daha çabuk geçiyor; böylece ekrandaki yanıtın, anahtarınızın çoktan geçersiz kıldığı bir yanıt olduğu süre kısalıyor.

## 0.3.66

**Başka bir uygulamanın içinde yaşayan bir uygulama artık onunla birlikte kapatılıp yeniden açılıyor.** Birkaç uygulama kendi paketinin içinde ikinci, eksiksiz bir uygulama taşıyor — Surge, Dashboard’unu orada tutuyor. macOS bunu ayrı bir uygulama olarak görüyor; bu yüzden çevresindeki uygulamaya bir güncelleme uygulandığında onu hiçbir şey kapatmıyordu: Az önce değiştirilen sürümü, artık sandığı yerde olmayan bir kopyadan çalıştırmaya devam ediyor ve bu noktadan sonra ait olduğu uygulamayla iletişim kuramıyordu. Bunlar artık içinde bulundukları uygulamayla birlikte kapatılıyor ve ondan sonra yeniden açılıyor; öne gelen pencere de gerçekte üzerinde çalıştığınız pencere oluyor. Bu şekilde yalnızca sizin de açabileceğiniz uygulamalar ele alınıyor; bir uygulamanın kendisi için çalıştırdığı görünmez yardımcı süreçlere dokunulmuyor.

**Sessizce oluşturulmaz hale gelen geri alma noktaları yeniden oluşturuluyor.** Bir uygulama kendi dosyalarından birini hiçbir şeyin silemeyeceği şekilde kilitleyebilir ve geri alma için tutulan kopya bu kilidi devralıyordu — bu yüzden bir sonraki kopyayla asla değiştirilemiyordu ve yarıda kesilen tek bir deneme, hiçbir şeyin temizleyemeyeceği bir kopya bırakabiliyordu. Bundan sonra o uygulamanın her güncellemesi geri dönüş yolu olmadan yapılıyor ve bu durum hiçbir neden belirtmeyen tek bir satırla bildiriliyordu. Geliştiricinin kendi Mac’indeki bir uygulama iki gündür bu durumdaydı. Geri alma için tutulan kopyalar artık kilidi taşımıyor, yüklü uygulama tam olarak geliştiricisinin ayarladığı gibi bırakılıyor ve takılı kalmış bir kopya artık yerini alması gereken kopyayı engelleyemiyor.

**Başarılı olan bir güncelleme artık başarısız olduğunu bildirmiyor.** macOS yeni bir sürümü yerine koyup ardından yerinden ettiği sürümü kaldırırken hata verebiliyor. Bu hata olduğu gibi kabul ediliyordu: DuoUpdater, güncellenmiş bir uygulamanın güncellenmediğini ya da yedek deposunda eksiksiz bir geri alma noktası dururken geri alma noktası olmadığını söylüyordu — ve ilk durumda sizi zaten vermiş olduğunuz ve her halükârda işe yaramayacak bir izni vermeye yönlendiriyordu. Artık bir şey bildirilmeden önce diskte gerçekte ne olduğu denetleniyor.

**Sürüm satırları artık sürüm numarasında zaten bulunan rakamları yinelemiyor.** Bir uygulama yeniden başlatılmayı beklerken satır, çalıştırdığınız sürümü ve yeniden başlatmanın getireceği sürümü gösterir. İki tarafta da bir derleme numarası vardı: Bu, geliştirici tek bir sürüm adı altında birkaç derleme yayımladığında farkı okunur kılar — sürümler zaten farklıysa ise saf gürültüdür. Chrome’un satırı genişliğini “151.0.7922.174 (7922.17…” yazmaya harcıyor ve gerçekten değişen rakamlara gelmeden yer kalmıyordu. Derleme numaraları artık yalnızca değişen şey onlar olduğunda görünüyor.

## 0.3.65

**Bir uygulamayı güncellemesini tamamlamak üzere yeniden açmak için artık tek bir sözcük var.** Kendi güncelleyicisi yeni sürümü çoktan yerine koymuş bir uygulama için “Restart” deniyordu; yeni sürümü siz kapatana kadar kenarda tutan bir uygulama için ise “Relaunch”. Bu fark perde arkasında gerçekti ama sizin için hiçbir şey değiştirmiyordu: Her iki durumda da aynı tıklama ve hiç tıklamazsanız aynı sonuç, çünkü güncelleme her halükârda uygulamayı bir sonraki kapatışınızda yerine geçiyor. Artık her yerde “Yeniden Başlat” yazıyor — bildirimlerde, ipuçlarında ve bunu sizin yerinize yapan ayarda da — ve bu, Chrome’un, Claude’un ve kendini güncelleyen çoğu uygulamanın karşınıza çıkardığı sözcükle de aynı. Bu iş için iki sözcüğü olan tek dil İngilizceydi; Almanca, Japonca, Rusça ve Çince her zaman tek bir sözcük kullandı; İspanyolca ve Fransızca da başka yerlerde zaten kullandıkları ifadeye geçiyor.

## 0.3.64

**Yönetici gerektiren bir güncelleme artık başarısız olup bir izni suçlamak yerine yönetici izni istiyor.** Bir değişimin parola gerektirip gerektirmediğine uygulamanın kendisine değil, bulunduğu klasöre bakılarak karar veriliyordu. macOS’un root olarak yüklediği her şey — her App Store uygulaması ve bir yükleyici paketinin yerleştirdiği her uygulama — bu testi geçiyor, parola gerektirmeyen yola giriyor ve işi asla tamamlayamıyordu: Eski sürümü kaldırmak, içindeki dizinlere yazma erişimi gerektiriyor. macOS bu reddi, reddedilmiş bir Uygulama Yönetimi izni için kullandığı kodla bildiriyor; bu yüzden hata, Uygulama Yönetimi izni verme isteği olarak geliyordu — oysa bu asla işe yaramazdı, çünkü engel dosya sahipliğiydi. Sıradan bir Mac’te bu, tüm App Store uygulamaları ve bunlara ek olarak birkaç uygulama demekti; sorun da yönetici hesaplarını etkiliyordu, çünkü standart hesaplar zaten doğru yola yönlendiriliyordu. Bu güncellemeler artık işe yarayan yolu izliyor ve uygulama, sessizce sizin olmak yerine önceki sahibini koruyor.

**App Store uygulamaları artık diğer her şey gibi bir geri alma noktası alıyor.** Yedeklemeler, mağazanın önceki bir derlemeyi her zaman geri getirebileceği varsayımıyla bunları atlıyordu. Getiremez — App Store yalnızca bir uygulamanın güncel sürümünü sunar; bu da mağazayı, bir güncellemeyi geri alma yolu olmadan uygulayan tek yol haline getiriyordu. Bu uygulamalar artık bir güncellemeden önce diğerleri gibi yedekleniyor ve kopya klonlanarak oluşturulduğu için, güncelleme orijinalin yerini gerçekten alana kadar neredeyse hiç disk alanı kaplamıyor. Birini geri yüklediğinizde mağazaya özgü durum belirtiliyor: Güncelleme, Güncellemeler listesinde hemen yeniden görünür ve otomatik uygulama güncellemeleri açıksa kendiliğinden yeniden uygulanır. Ayrıca bir mağaza güncellemesinin zaten hiç uygulanmayacağı durumlarda — Mac’te çalışan bir iPhone uygulaması ya da bölgenizde satılmayan bir ürün — artık geri alma noktası oluşturulmuyor; böylece bir satır, zaten çalıştırdığı sürüme geri almayı öneremiyor.

**Longbridge Desktop artık iki sürüm hattında da izleniyor.** Stable ve Preview hatlarının her biri sürüm algılama, resmi Apple silicon derlemesinin tek tıkla yüklenmesi ve DuoUpdater’ın kendi penceresinde görselleriyle birlikte gösterilen sürüm notları alıyor.

**WhatsApp’ın sürüm notları artık App Store denetimi hâlâ sürerken görünüyor.** O pencerede gösterilen App Store sayfası, aramanın asla eşleştiremeyeceği bir ad altında kaydedilmişti; bu yüzden notlar bölmesi onu göstermek yerine boş kalıyordu.

**Menü başlığı daha az yerde daha fazlasını taşıyor.** DuoUpdater’ın kendi sürümü artık adının yanında duruyor ve üzerine tıklamak sürüm notlarını açıyor. “Tümünü Güncelle” kendi satırına taşındı; çevrilmiş bir etiket orada tamamen okunabilecek kadar yer buluyor. Alttaki eylemler de artık simge olarak gösteriliyor. DuoUpdater’ın kendini güncellediğini duyuran afiş kaldırıldı — onun yerine sürümün yanındaki pırıltı simgesi yanıyor ve neyin değiştiğini okuyana kadar yanık kalıyor. Menüye sığmayacak kadar uzun bir durum satırı artık menüyü genişletmek yerine üç noktayla bitiyor.

**Ayarlar artık sunduğu güncelleme seçeneklerini kırpmıyor.** Bir güncellemenin nasıl uygulanacağını belirleyen iki menü, birkaç dilde kendi etiketlerini kırpıyordu. İfadeler artık daha kısa ve sözcüklerin hâlâ sığmadığı yerlerde ikinci bir satıra geçiyor.

**Yenilikler artık her sürümün ne zaman yayımlandığını gösteriyor.** Kenar şeridindeki her sürüm artık yayım tarihini taşıyor.

## 0.3.63

**Mimariye özgü güncellemeler artık bu Mac’in gerçekten çalıştırabileceği derlemeyi seçiyor.** Birkaç uygulama aynı sürümü tek bir Sparkle akışında iki kez yayımlıyor — bir kez Apple silicon, bir kez Intel için — ve DuoUpdater bu eşitliği, hangi indirme adresi sıralamada önce geliyorsa onu seçerek bozuyordu. Artık akışın donanım gereksinimini, üreticinin bunu boş bıraktığı durumlarda ise dosya adındaki mimariyi okuyor. Yerel derleme tutarlı biçimde tercih ediliyor ve bu Mac’in açamayacağı bir derleme sunulmuyor. GitHub sürümleri de aynı şekilde ele alınıyor; üstelik en yeni dosyası başka bir mimariyi hedefliyor diye son derece sağlıklı bir tarife bozuk denmeden.

**ChatGPT güncelleme denetimleri artık hesaba bağlı dağıtım hattını izliyor.** OpenAI zaman zaman yeni bir derlemeyi önce bireysel hesaplara ulaştırırken işletme ve kurumsal hesapları daha eski bir masaüstü derlemesinde tutuyor. DuoUpdater eskiden bu denetimde hesabın planını göndermiyordu; bu da herkes için sessizce temkinli hattı seçiyordu: ChatGPT’nin kendisi daha yeni bir derlemeyi çoktan indirirken yüklü kopyanın bir şekilde ileride olduğunu söyleyebiliyor ya da uygulamanın kendi güncelleyicisinin yeniden değiştireceği bir derleme sunabiliyordu. Artık plan etiketini ChatGPT/Codex oturum açma durumundan alıp uygulamanın yaptığı güncelleme isteğinin aynısıyla gönderiyor. Bu etiket kullanılamıyorsa temkinli davranışı sürdürüyor; kimlik bilgilerinin kendisi hiçbir zaman isteğe ya da tanılama verilerine konmuyor.

**macOS’un hiç yanıtlamadığı bir yeniden başlatma artık sonraki tüm güncellemeleri kilitleyemiyor.** Launch Services zaman zaman güncellenmiş bir uygulamayı yeniden açma isteğini kabul ediyor ve sonra hiç geri dönmüyor. Satır sonsuza dek “Yeniden başlatılıyor…” durumunda kalıyor, Yeniden Başlat düğmesi devre dışı kalmaya devam ediyor ve DuoUpdater’ın kendi güncellemesi de bunun arkasında bekliyordu. Bir dakika sonra hâlâ yanıt vermemiş bir başlatma artık başarısız sayılıp bırakılıyor; böylece satır toparlanıyor ve güncelleyicinin geri kalanı çalışmaya devam ediyor.

**Sürüm Günlüğü, kaydırma çubuğu hızla sürüklendiğinde artık boş kalmıyor.** Eski tembel yığın uzun bir sıçramaya yetişemeyebiliyor ve yeni konumun çevresinde satırlar oluşturulurken pencereyi kısa bir süre boş bırakabiliyordu. Günlük artık doğrudan hedefe atlayabilen, satırları yeniden kullanan bir liste kullanıyor. Yenileme düğmesi de ok ile dönen gösterge arasında geçiş yaparken aynı yeri kaplıyor; böylece bir denetim başladığında alt satır artık seğirmiyor.

**İndirme Trafiği artık ikili yama kullanan güncellemeleri işaretliyor.** Yeni indirmeler, yalnızca bir yamanın sunulup sunulmadığını değil, gerçekte tamamlanan yolu kaydediyor ve geçmişlerinde bir Delta rozeti taşıyor. 0.3.62’deki belirgin biçimde daha küçük yama indirmeleri de, trafik kaydında henüz bir yol alanı yokken kaydedilmiş olsalar bile tanınıyor.

## 0.3.62

**Geliştirici bu şekilde yayımladığında güncellemeler artık yalnızca değişen kısmı indiriyor.** Bazı uygulamalar her sürümün yanında küçük bir yama yayımlıyor — elinizdeki sürümü, her şeyi yeniden indirmeden yenisine dönüştürmeye yetecek kadar. DuoUpdater eskiden bunları yok sayıyor ve her seferinde paketin tamamını indiriyordu. Artık tam olarak kullandığınız derlemeyle eşleşen bir yama varsa onu alıyor. ChatGPT’nin son güncellemesi 605 MB yerine 1,9 MB tuttu; Docker’ınki 582 MB yerine 87 MB. Sonuç her iki yolda da aynı uygulama — aynı imza, aynı baytlar; bu, yayımlanmadan önce tam indirmeyle karşılaştırılarak doğrulandı. Elinizdekine uyan bir yama yoksa ya da yama uygulanamazsa tam indirme eskisi gibi yapılıyor; bu yüzden bu değişiklik hiçbir şeyin yüklenememesine yol açamaz.

**DuoUpdater artık bir uygulamanın zaten kendisinin indirdiği bir güncellemeyi indirmiyor.** Pek çok uygulama kendini de güncelliyor ve ikimizin aynı anda aynı 600 MB’lık dosyaya uzanması, o dosyayı size iki kez indirtiyordu. DuoUpdater artık süren bir indirmeyi fark edip ona dokunmuyor ve sessizce hiçbir şey yapmamak yerine bunu satırda belirtiyor. O indirme yarıda bırakılmış çıkarsa on dakika sonra dikkate alınmayı bırakıyor; böylece hiçbir şey engellenmiş halde kalmıyor.

**Bir uygulamanın zaten hazırladığı bir güncellemenin üzerine artık yazılmıyor.** Kendini güncelleyen uygulamalar çoğu zaman arka planda indirir ve yeni sürümü yerine koymak için sizin onları kapatmanızı bekler. Bunlardan birinin üzerine yüklemek işe yaramış gibi görünüyor, sonra uygulamayı kapattığınız anda boşa çıkıyordu — ve uygulamanın bekleyen kendi sürümü DuoUpdater’ın az önce yüklediğinden eskiyse, başladığınız noktadan da geride kalıyordunuz. Bu güncellemelerin, hangi sürümü taşırlarsa taşısınlar, artık tamamlanmasına izin veriliyor.

**DuoUpdater’ın kendi güncellemeleri de küçüldü.** Sürümleri artık aynı türden bir yamayla geliyor; bu yüzden yakın tarihli bir sürümden güncellemek on bir megabayt yerine birkaç yüz kilobayt indiriyor.

## 0.3.61

**Bir güncellemenin geride bıraktığı açıklamalar artık kendiliğinden temizleniyor.** DuoUpdater bir uygulamayı kendi güncelleyicisine devrettiğinde satır bunu belirtir: “Kendi güncelleyicisi güncellemeyi uygulasın diye öne getirildi.” Bu cümle eskiden kalıcı olarak orada kalıyordu: Onu kaldıran tek şey aynı uygulamada başka bir güncelleme başlatmaktı; bu yüzden güncelleme gerçekleştikten çok sonra bile satırın altında duruyor ve saatler önce bitmiş bir şeyi anlatıyordu. Artık uygulama güncel hale gelir gelmez kayboluyor. Bir güncellemenin geri alma noktası olmadan uygulandığına dair uyarıya ise bilerek dokunulmuyor, çünkü o uyarı zaten gerçekleşmiş güncellemeyi anlatıyor ve ancak güncelleme bittikten sonra önem kazanıyor.

**Reddedilen bir güncelleme artık nedenini sizin dilinizde açıklıyor.** Başka bir şey zaten yükleme yaparken — bir grup güncellemeyi sırayla işleyen DuoUpdater ya da bir terminaldeki `duo` — satır bunu size söyler. Bu mesaj, geri kalanı çevrilmiş bir pencerede yalnızca İngilizceydi ve bir süreç numarasıyla bitiyordu: Bu numara terminalde işe yarar, bir menüde ise üzerinde işlem yapabileceğiniz bir şey değildir. Mesaj artık çevrildi ve kilidi kimin tuttuğunu değil, ne yapmanız gerektiğini söylüyor. Komut satırı aracı ise süreç numarasını, onunla bir şey yapabileceğiniz yer olduğu için hâlâ yazdırıyor.

**Sürüm deseni satırı ve saati artık yerel ayarlarınıza uyuyor.** Sürüm Günlüğü → Desenler her şeyi “En sık Cuma, saat 18.00 civarında yayımlıyor” diye özetliyordu. Gün adlarını çekimleyen diller, gün cümlenin ortasına yerleştirildiğinde bunu doğru söyleyemiyor ve sözcüğün yanlış biçimini alıyordu — Rusçada “по пятницам” olması gereken yerde “Чаще всего выходит пятница” yazıyordu. Artık bu bir etiket: “Zirve: Cuma, yaklaşık 18.00” — her dilde doğru. Saat de buna uyuyor: Mac’iniz saatleri 24 saat biçiminde yazıyorsa bu satır da öyle yazıyor, grafiğin ekseni de.

**Ayarlar araması artık ekranınızdaki sözcükleri anlıyor.** Ayarlar kenar çubuğunun üstündeki arama alanı, İngilizce yazılmış ve hiç çevrilmemiş ek terimlerden oluşan bir listeyle eşleştirme yapıyordu; bu yüzden “rollback” Genel bölümüne ulaşırken “Zurücksetzen” ve “回滚” hiçbir yere ulaşmıyordu. Bu terimler artık DuoUpdater’ın konuştuğu her dilde var. İngilizce terimler de, kaynaklandıkları belgeler İngilizce olduğu için her dilde çalışmaya devam ediyor.

## 0.3.60

**“Tümünü göster”i açmak artık menüyü duraksatmıyor.** Sahip olduğunuz tüm uygulamaların tam listesi her görüntülendiğinde baştan sona ölçülüyordu — 127 uygulamalı bir Mac’te bu yaklaşık bir saniyelik iş demekti ve neredeyse tamamı, görebildiğiniz satırların çok altındaki satırları yerleştirmeye harcanıyordu. Bu bedel yalnızca ilk seferde değil, her açıp kapamada ödeniyordu. Artık yalnızca ekranda gerçekten görünen satırlar oluşturuluyor.

**Başarısız bir güncellemeden kalan açıklama artık hatanın kendisinden uzun yaşamıyor.** Bir güncelleme uygulanamadığında — örneğin başka bir şey zaten yükleme yaptığı için — satır bunun nedenini kırmızıyla belirtiyordu. O satırı hiçbir şey kaldırmıyordu: Güncelleme sonunda gerçekleşip satır yeniden onay işaretine döndüğünde eski açıklama hâlâ altında duruyor ve DuoUpdater yeniden başlatılana kadar her yeniden denetimde orada kalıyordu. Artık uygulama güncel hale gelir gelmez kayboluyor. Hâlâ bekleyen güncellemelere ait nedenlere dokunulmuyor; böylece henüz okumadığınız bir neden, arka planda çalışan bir denetim tarafından silinemiyor.

**“Tümünü Güncelle” düğmesi artık listenin uzunluğuna göre boyut değiştirmiyor.** Bekleyen yalnızca birkaç güncelleme olduğunda olması gerekenden bir boy küçük çiziliyor, yanında seksen punto boşluk kalıyor ve liste uzadığında doğru boyutuna geri sıçrıyordu. Artık hep olması gereken boyutta kalıyor.

## 0.3.59

**İndirme Trafiği artık bir güncellemenin yalnızca hangi sürüme değil, hangi derlemeye geçtiğini de gösteriyor.** Pek çok uygulama tek bir sürüm adı altında birkaç derleme yayımlıyor — Surge dört ayrı sürümü “6.9.0” adıyla çıkardı — bu yüzden o satırlarda “6.9.0 → 6.9.0” yazıyor ve size hiçbir şey anlatmıyordu. Artık “6.9.0 (12028) → 6.9.0 (12030)” yazıyor, ama yalnızca sürüm adı tek başına yetmediğinde; sürümün zaten değiştiği yerlerde derleme numarası yalnızca gürültü olacağı için gösterilmiyor.

**Kaydedilen derleme, gerçekte yerine oturan derleme; güncelleme tamamlandıktan sonra doğrudan uygulamanın kendisinden okunuyor.** Geliştiricinin güncelleme akışının duyurduğu numara değil — akışlar bazen yanlış bilgi veriyor ve bu yöntem, hiç derleme numarası yayımlamayan yerlerde de çalışıyor: GitHub, Homebrew ve App Store. macOS’un yükleyici penceresini hâlâ bekleyen bir güncelleme için asla tahmin yürütülmüyor; gerçekleşene kadar onun için hiçbir şey kaydedilmiyor.

**Hiçbir şeyi değiştirmeyen bir indirme artık öyle işaretleniyor.** Bir güncelleme ara sıra Mac’inizde zaten bulunan derlemeyi indirip yüklüyor — geliştirici tarafında bir sürüm numarası uyuşmazlığı ya da elinizdekini sunan bir yansı sunucu yüzünden. Bu, sonuç getirmeden harcanan gerçek bir bant genişliği ve bunu görmek isteyeceğiniz yer de trafik penceresi. Bu satırlar artık “değişiklik yok” etiketi taşıyor. Bu sürümden önce kaydedilen indirmelerde karşılaştırılacak derleme numarası yok; bu yüzden onlar hakkında tahmin yürütülmüyor, olduğu gibi bırakılıyorlar: Bilinmeyen, değişmemiş demek değildir.

## 0.3.58

**DuoUpdater artık uygulamalarınızı güncel tutmanın indirme açısından size gerçekte neye mal olduğunu gösteriyor.** Sizin için indirdiği her güncellemeyi bayt bayt sayıyordu — ama bu sayının görünebileceği bir yer yoktu; sayı kimsenin okuyamadığı bir dosyada duruyordu. Artık menünün altındaki grafik düğmesiyle açılan bir İndirme Trafiği penceresi var; bu ayın rakamı da o düğmenin yanında yazıyor, böylece en sık sorulan soru hiçbir şey açmadan yanıtlanıyor. İçeride şunlar var: toplam, son üç ay yan yana ve aralarındaki değişim, baytların nereden geldiğinin dökümü ve neye mal olduklarına göre sıralanmış tüm uygulamalar. Birine tıklayarak aldığı her güncellemeyi, hangi sürümden hangisine geçtiğini ve o indirmenin ne kadar büyük olduğunu görebilirsiniz.

**Toplam, göremediği şeyler konusunda dürüst.** Homebrew, App Store ve kendi yerleşik güncelleyicisiyle güncellenen uygulamalar kendi baytlarını kendileri indiriyor ve DuoUpdater bunlara hiç dokunmuyor — bu yüzden rakam eksiksiz bir hesap değil, bir alt sınır. Bu hep böyleydi; değişen şu: Pencere artık bunu yalnızca henüz hiçbir şey kaydedilmemişken gördüğünüz boş ekranda değil, kalıcı olarak belirtiyor.

**Sonradan yeniden adlandırdığınız ya da sildiğiniz uygulamaların geçmişi korunuyor.** Trafik, bir uygulamanın diskte bulunduğu yere göre kaydediliyor; aynı uygulamanın iki kanalının — örneğin Android Studio Canary ve Beta — toplanmak yerine ayrı kalmasını sağlayan da bu. Bedeli ise bir uygulamayı yeniden adlandırmanın, geçmişini artık var olmayan bir adın altında bırakması. OpenAI, Codex’in adını ChatGPT olarak değiştirdiğinde bu, 30 GB’lık indirmeyi birbirinin kopyası gibi görünen iki girdiye böldü. Bu girdiler artık listenin en altında, ne olduklarını belirten bir başlık altında gruplanıp soluk gösteriliyor. Hiçbir şey atılmıyor ve toplam onları da içeriyor.

## 0.3.57

**App Store’dan yüklediğiniz bir uygulamaya artık geliştiricinin kendi indirmesi sunulmuyor.** Pek çok uygulama aynı anda iki yerde yayımlanıyor — mağazada ve geliştiricinin kendi sitesinde doğrudan indirme olarak — aynı kimlikle, ama gerçekten farklı derlemeler olarak. Doğrudan indirme mağaza incelemesini beklemediği için genellikle öndedir. DuoUpdater mağazadan yüklenmiş bir uygulama için önce mağazayı denetliyor, ancak bu denetim herhangi bir nedenle — kopan bir bağlantı, yanıt vermeyen bir mağaza bölgesi — başarısız olduğunda sessizce geliştiricinin sitesine geçiyor ve orada ne varsa onu sunuyordu. WhatsApp bunu “26.32.75 → 26.33.19” olarak gösterdi: gerçek bir sürüm, ama yanlış yerden. Bunu almak, mağaza kopyanızı App Store’un bir daha asla güncelleyemeyeceği bir kopyayla değiştirirdi. Mağazadan yüklenen uygulamalar artık yalnızca mağazaya göre denetleniyor.

**Bir uygulamanın güncelleme kanalını o uygulamanın içinden değiştirmek artık hemen algılanıyor.** Bazı uygulamalar normal sürümleriyle beta sürümleri arasında seçim yapmanıza izin veriyor — Surge, Tailscale, Fork, OrbStack, IINA, Alfred ve diğerleri — ve DuoUpdater, istemediğiniz bir derlemeyi asla sunmamak için hangisini seçtiyseniz onu izliyor. Eskiden bu değişikliği yalnızca uygulamayı kapattığınızda ya da DuoUpdater’ın pencerelerinden birini açtığınızda fark ediyordu. İkisi de insanların gerçekte yaptığını kapsamıyor: ayarı kapatmak, uygulamayı açık bırakmak ve menü çubuğuna bir göz atmak. Daha kötüsü, uygulamalar bu ayarı tıkladığınız anda değil, işlerine geldiğinde diske kaydediyor — burada Surge için bu beş dakika sürdü — bu yüzden uygulamayı kapattığınızda bile ayar çok erken okunabiliyordu. DuoUpdater artık ayarın kendisindeki değişikliği izliyor ve o tek uygulamayı bir iki saniye içinde yeniden denetliyor. Surge normal sürümlere geri döndürüldüğünde beta sürümü, bir saate kadar satırda kalmak yerine artık hemen kayboluyor.

**Hiçbir yere ulaşamayan bir denetim artık her şey yolundaymış gibi görünmüyor.** Tüm kaynaklar başarısız olduğunda — ağ yoksa ya da Wi-Fi simgesi her şeyin yolunda olduğunu söylerken bir proxy bağlantıları sessizce reddediyorsa — başarısız olan uygulamalar gizleniyor ve panelde “127 uygulama · güncel” yazıyordu. Bu, her şey gerçekten güncel olduğunda gördüğünüz ekranın aynısıydı ve başarısız bir denetimi başarılı olandan ayırt edilemez hale getiriyordu. Panel artık kaç uygulamaya ulaşamadığını söylüyor, neyin ters gittiğini gösteriyor ve yalnızca onları yeniden denemeyi öneriyor — denetleyebildiği her şeye dokunmadan.
