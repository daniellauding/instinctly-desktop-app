# Instinctly Web Viewer

This web page displays images shared via Instinctly's CloudKit sharing feature.

## Setup Instructions

### Step 1: Generate CloudKit API Token

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
2. Select your container: `iCloud.com.instinctly.app`
3. Click **API Access** in the sidebar
4. Click **Create New Token**
5. Give it a name like "Web Viewer"
6. Copy the generated API token

### Step 2: Configure the Web Viewer

1. Open `index.html`
2. Find the `CLOUDKIT_CONFIG` section (around line 135)
3. Replace `YOUR_API_TOKEN_HERE` with your actual API token:

```javascript
const CLOUDKIT_CONFIG = {
    containerIdentifier: 'iCloud.com.instinctly.app',
    apiTokenAuth: {
        apiToken: 'paste-your-token-here',  // <-- Replace this
        persist: true
    },
    environment: 'production'
};
```

### Step 3: Host the Web Page

#### Option A: GitHub Pages (Free)

1. Create a new GitHub repository (e.g., `instinctly-share`)
2. Upload `index.html` to the repository
3. Go to Settings → Pages
4. Set Source to "main" branch
5. Your URL will be: `https://yourusername.github.io/instinctly-share`

#### Option B: Vercel (Free)

1. Go to [vercel.com](https://vercel.com)
2. Import from GitHub or drag-drop the folder
3. Deploy automatically
4. Your URL will be: `https://your-project.vercel.app`

#### Option C: Netlify (Free)

1. Go to [netlify.com](https://www.netlify.com)
2. Drag-drop the Web folder
3. Deploy automatically
4. Your URL will be: `https://your-site.netlify.app`

### Step 4: Update the App

Once hosted, update the URL in the Instinctly app:

1. Open `Instinctly/Services/ShareService.swift`
2. Find `webViewerBaseURL`
3. Update it to your hosted URL:

```swift
private let webViewerBaseURL = "https://yourusername.github.io/instinctly-share"
```

## Testing

After setup, share an image from Instinctly. The generated URL should look like:

```
https://yourusername.github.io/instinctly-share?id=UUID-HERE
```

Opening this URL in a browser should display the shared image.

## Troubleshooting

### "CloudKit API token not configured"
- Make sure you replaced `YOUR_API_TOKEN_HERE` with your actual token

### "Image not found"
- Verify the CloudKit container has the record
- Check the CloudKit Dashboard → Data to see if records exist

### "Authentication required"
- CloudKit public database should work without auth
- Ensure your container is set to allow public reads

## Custom Domain

To use a custom domain like `share.instinctly.app`:

1. Add a CNAME record pointing to your hosting provider
2. Configure the custom domain in your hosting settings
3. Update `webViewerBaseURL` in the app

## Security Notes

- The API token only provides read access to public data
- Never commit API tokens to public repositories
- Consider using environment variables for the token in production
