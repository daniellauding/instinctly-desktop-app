import SwiftUI

/// Firebase Authentication View for login and registration
/// Note: This is prepared for Firebase but currently works as a UI template
/// Firebase SDK needs to be added and configured separately
struct FirebaseAuthView: View {
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingAlert = false
    
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @AppStorage("userEmail") private var userEmail = ""
    @AppStorage("userDisplayName") private var userDisplayName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)
                
                Text(isLoginMode ? "Welcome Back" : "Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(isLoginMode ? "Sign in to continue" : "Join Instinctly today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            
            // Form
            VStack(spacing: 20) {
                if !isLoginMode {
                    HStack {
                        Image(systemName: "person")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        TextField("Display Name", text: $displayName)
                            .textFieldStyle(.plain)
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                HStack {
                    Image(systemName: "envelope")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                }
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                HStack {
                    Image(systemName: "lock")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                }
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                if !isLoginMode {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(.plain)
                            .textContentType(.password)
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Action Button
                Button(action: authenticate) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text(isLoginMode ? "Sign In" : "Create Account")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(isLoading || !isFormValid)
                
                // Toggle Mode
                Button(action: { isLoginMode.toggle() }) {
                    HStack {
                        Text(isLoginMode ? "Don't have an account?" : "Already have an account?")
                            .foregroundColor(.secondary)
                        Text(isLoginMode ? "Sign Up" : "Sign In")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Footer
            VStack(spacing: 16) {
                Divider()
                    .padding(.horizontal, 40)
                
                VStack(spacing: 8) {
                    Text("Or continue with")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        SocialSignInButton(provider: .google)
                        SocialSignInButton(provider: .apple)
                        SocialSignInButton(provider: .github)
                    }
                }
                
                // Continue without account (iCloud only mode)
                Button(action: continueWithoutAccount) {
                    Text("Continue with iCloud Only")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 450, height: 650)
        .alert("Error", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var isFormValid: Bool {
        if isLoginMode {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !email.isEmpty && !password.isEmpty && 
                   !displayName.isEmpty && password == confirmPassword &&
                   password.count >= 6
        }
    }
    
    private func authenticate() {
        isLoading = true
        errorMessage = ""
        
        // TODO: Implement Firebase authentication here
        // For now, this is a placeholder that simulates authentication
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if isLoginMode {
                // Simulate login
                if email.contains("@") && !password.isEmpty {
                    isAuthenticated = true
                    userEmail = email
                    userDisplayName = email.components(separatedBy: "@").first ?? "User"
                } else {
                    errorMessage = "Invalid email or password"
                    showingAlert = true
                }
            } else {
                // Simulate registration
                if password != confirmPassword {
                    errorMessage = "Passwords don't match"
                    showingAlert = true
                } else if password.count < 6 {
                    errorMessage = "Password must be at least 6 characters"
                    showingAlert = true
                } else {
                    isAuthenticated = true
                    userEmail = email
                    userDisplayName = displayName
                }
            }
            isLoading = false
        }
    }
    
    private func continueWithoutAccount() {
        // Allow user to use app with iCloud only (no Firebase features)
        isAuthenticated = true
        userEmail = "icloud-only@local"
        userDisplayName = "iCloud User"
    }
}

// MARK: - Social Sign In Button
struct SocialSignInButton: View {
    let provider: SocialProvider
    @State private var isHovered = false
    
    enum SocialProvider {
        case google, apple, github
        
        var icon: String {
            switch self {
            case .google: return "globe"
            case .apple: return "apple.logo"
            case .github: return "link"
            }
        }
        
        var name: String {
            switch self {
            case .google: return "Google"
            case .apple: return "Apple"
            case .github: return "GitHub"
            }
        }
    }
    
    var body: some View {
        Button(action: signIn) {
            VStack(spacing: 4) {
                Image(systemName: provider.icon)
                    .font(.title2)
                Text(provider.name)
                    .font(.caption)
            }
            .frame(width: 80, height: 60)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func signIn() {
        // TODO: Implement social sign-in
        print("Sign in with \(provider.name)")
    }
}

#Preview {
    FirebaseAuthView()
}