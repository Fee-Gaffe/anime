import SwiftUI
import WebKit

struct ContentView: View {
    @State private var isShowingLoadingScreen = true
    @State private var isShowingDownloadAlert = false
    @State private var isShowingLoginView = false
    @State private var userId: Int? = nil // userId est initialisé à nil

    var body: some View {
        NavigationView {
            ZStack {
                WebView(url: URL(string: "https://anime-sama.fr")!, isShowingLoadingScreen: $isShowingLoadingScreen)
                    .navigationBarHidden(true)
                    .background(Color.black.edgesIgnoringSafeArea(.all))
                
                VStack {
                    Spacer()
                    Button(action: {
                        if userId == nil {
                            self.isShowingLoginView = true
                        } else {
                            downloadLocalStorageFile()
                        }
                    }) {
                        Text("Syncroniser")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.bottom, 20)
                }
                
                if isShowingLoginView {
                    LoginView(isShowing: $isShowingLoginView, userId: $userId)
                        .background(Color.black.opacity(0.5).edgesIgnoringSafeArea(.all))
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.isShowingLoadingScreen = false
                }
            }
            .alert(isPresented: $isShowingDownloadAlert) {
                Alert(
                    title: Text("Téléchargement terminé"),
                    message: Text("L'historique à été téléchargé avec succès."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    func downloadLocalStorageFile() {
        // Vérifier que userId n'est pas nil
        guard let userId = userId else {
            print("User ID is nil. Please log in first.")
            return
        }
        
        print("User ID during download: \(userId)")
        
        let fileManager = FileManager.default
        let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let webkitDataDirectory = libraryDirectory.appendingPathComponent("WebKit/WebsiteData/Default")

        if let localStoragePath = findLocalStorageFile(in: webkitDataDirectory) {
            let url = URL(string: "https://feegaffe.fr/histo/api.php")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let boundary = UUID().uuidString
            let mimeType = "application/octet-stream"
            let fileData = try? Data(contentsOf: localStoragePath)
            
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            
            // Ajouter userId au corps de la requête
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"userId\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
            body.append("\(userId)\r\n".data(using: .utf8)!)
            
            // Ajouter le fichier SQLite au corps de la requête
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"sqliteFile\"; filename=\"\(localStoragePath.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData ?? Data())
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error uploading file: \(error)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    print("Error: Invalid response from server")
                    return
                }
                
                if let data = data {
                    // Sauvegarder le fichier JSON localement
                    let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let jsonFileURL = documentDirectory.appendingPathComponent("data.json")
                    
                    do {
                        try data.write(to: jsonFileURL)
                        
                        // Maintenant, téléverser le fichier JSON vers une autre API
                        uploadJSONFile(jsonFileURL: jsonFileURL, userId: userId)
                    } catch {
                        print("Error saving JSON file: \(error)")
                    }
                }
            }.resume()
        } else {
            print("Local storage file not found.")
        }
    }

    func uploadJSONFile(jsonFileURL: URL, userId: Int) {
        let url = URL(string: "https://feegaffe.fr/histo/upload.php")! // Updated API endpoint
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        let boundaryPrefix = "--\(boundary)"
        let boundarySuffix = "\(boundaryPrefix)--"

        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Ajouter userId au corps de la requête
        body.append("\(boundaryPrefix)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userid\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)

        // Ajouter le fichier JSON
        body.append("\(boundaryPrefix)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"jsonfile\"; filename=\"data.json\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        
        if let fileData = try? Data(contentsOf: jsonFileURL) {
            body.append(fileData)
        } else {
            print("Erreur lors de la lecture du fichier JSON")
            return
        }

        body.append("\r\n".data(using: .utf8)!)
        body.append(boundarySuffix.data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Erreur lors de l'envoi du fichier JSON : \(error)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Erreur : Réponse invalide du serveur")
                return
            }

            DispatchQueue.main.async {
                self.isShowingDownloadAlert = true
            }
        }.resume()
    }

    func findLocalStorageFile(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        let localStorageFileName = "localstorage.sqlite3"
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            for item in contents {
                if item.lastPathComponent == localStorageFileName {
                    return item
                }
                
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    if let found = findLocalStorageFile(in: item) {
                        return found
                    }
                }
            }
        } catch {
            print("Error searching directory: \(error.localizedDescription)")
        }
        
        return nil
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isShowingLoadingScreen: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No need to implement anything here in this case
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isShowingLoadingScreen = false
            
            // JavaScript code to inject styles and remove specific elements
            let jsCode = """
                     const color = '#000411';
                     const newStyle = `
                         body {
                             background-color: ${color} !important;
                             background-image: none !important;
                         }
                         [href*="https://youradexchange.com/"],
                         [src*="https://youradexchange.com/"] {
                             display: none !important;
                         }
                         img[src*="https://cdn.statically.io/gh/Anime-Sama/IMG/img/autres/flag_pal.png"] {
                             display: none !important;
                         }
                         img.logo-circular {
                             border-radius: 50%;
                             transition: transform 0.5s ease;
                         }
                         img.logo-circular:hover {
                             transform: rotate(360deg);
                         }
                     `;
                     function injectStyle() {
                         const style = document.createElement('style');
                         style.type = 'text/css';
                         style.innerHTML = newStyle;
                         document.head.appendChild(style);
                     }
                     function replaceLogo() {
                         const logos = document.querySelectorAll('img[src*="https://cdn.statically.io/gh/Anime-Sama/IMG/img/autres/logo_banniere.png"]');
                         logos.forEach((logo) => {
                             logo.src = 'https://feegaffe.fr/logo.png';
                             logo.classList.add('logo-circular');
                         });
                     }
                     function observeLogo() {
                         const observer = new MutationObserver((mutations) => {
                             mutations.forEach((mutation) => {
                                 if (mutation.addedNodes.length > 0 || mutation.type === 'attributes') {
                                     replaceLogo();
                                 }
                             });
                         });
                         observer.observe(document.body, {
                             childList: true,
                             subtree: true,
                             attributes: true
                         });
                     }
                     injectStyle();
                     observeLogo();
                     const paypalLink = document.querySelector('a[href="https://www.paypal.com/donate/?hosted_button_id=3FBNLMGT3JAJ2"]');
                     if (paypalLink) {
                         paypalLink.remove();
                     }
                     """
            
            webView.evaluateJavaScript(jsCode, completionHandler: nil)
        }
    }
}



struct LoginView: View {
    @Binding var isShowing: Bool
    @Binding var userId: Int? // Assurez-vous que le type est Int?
    @State private var username = ""
    @State private var password = ""
    @State private var isError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack {
            Text("Connexion")
                .font(.headline)
                .padding()

            TextField("Nom d'utilisateur", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            SecureField("Mot de passe", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: {
                authenticateUser()
            }) {
                Text("Se connecter")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()

            if isError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .frame(width: 300, height: 200)
    }

    func authenticateUser() {
        guard let url = URL(string: "https://feegaffe.fr/login.php") else {
            print("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "username": username,
            "password": password
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Authentication error: \(error)")
                DispatchQueue.main.async {
                    self.isError = true
                    self.errorMessage = "Erreur de connexion. Veuillez réessayer."
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.isError = true
                    self.errorMessage = "Aucune donnée reçue du serveur."
                }
                return
            }

            do {
                let result = try JSONDecoder().decode(AuthenticationResult.self, from: data)
                if result.success, let userId = result.userId {
                    DispatchQueue.main.async {
                        self.userId = userId
                        self.isShowing = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isError = true
                        self.errorMessage = result.message ?? "Erreur de connexion. Veuillez réessayer."
                    }
                }
            } catch {
                print("JSON decoding error: \(error)")
                DispatchQueue.main.async {
                    self.isError = true
                    self.errorMessage = "Erreur de traitement des données. Veuillez réessayer."
                }
            }
        }.resume()
    }
}

struct AuthenticationResult: Codable {
    let success: Bool
    let userId: Int? // Assurez-vous que c'est de type Int?
    let message: String?
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
