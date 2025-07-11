import { serve } from "bun";

const API_SERVER_URL = process.env.API_URL || "http://localhost:10000";
const STATIC_FILES_PATH = "chat_web/build/web";

// MIME type mapping for better content type detection
const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.eot': 'application/vnd.ms-fontobject',
};

function getContentType(pathname: string): string {
  const ext = pathname.substring(pathname.lastIndexOf('.')).toLowerCase();
  return MIME_TYPES[ext] || 'application/octet-stream';
}

async function serveStaticFile(pathname: string): Promise<Response> {
  try {
    // Default to index.html for root path
    if (pathname === '/') {
      pathname = '/index.html';
    }
    
    const filePath = `${STATIC_FILES_PATH}${pathname}`;
    const file = Bun.file(filePath);
    
    // Check if file exists
    if (!(await file.exists())) {
      // For SPA routing, fallback to index.html for non-API routes
      const indexFile = Bun.file(`${STATIC_FILES_PATH}/index.html`);
      if (await indexFile.exists()) {
        console.log(`📄 SPA fallback: ${pathname} → /index.html`);
        return new Response(await indexFile.text(), {
          headers: { 
            'Content-Type': 'text/html',
            'Cache-Control': 'no-cache'
          }
        });
      }
      
      return new Response('File not found', { 
        status: 404,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
    
    const contentType = getContentType(pathname);
    console.log(`📁 Static: ${pathname} (${contentType})`);
    
    return new Response(file, {
      headers: {
        'Content-Type': contentType,
        'Cache-Control': pathname.endsWith('.html') ? 'no-cache' : 'public, max-age=31536000'
      }
    });
    
  } catch (error) {
    console.error('❌ Static file error:', error);
    return new Response('Internal server error', { 
      status: 500,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
}

async function proxyToAPI(req: Request, pathname: string): Promise<Response> {
  try {
    const url = new URL(req.url);
    // Remove /api prefix and forward to API server
    const apiPath = pathname.replace('/api', '');
    const apiUrl = `${API_SERVER_URL}${apiPath}${url.search}`;
    
    console.log(`🔄 API Proxy: ${pathname} → ${apiUrl}`);
    console.log(`🔄 API_SERVER_URL: ${API_SERVER_URL}`);
    console.log(`🔄 Method: ${req.method}, Headers:`, Object.fromEntries(req.headers.entries()));
    
    // Forward the request to the API server
    // Filter out problematic headers
    const forwardHeaders = new Headers();
    for (const [key, value] of req.headers.entries()) {
      // Skip headers that could cause routing issues
      if (!['host', 'connection', 'upgrade', 'keep-alive'].includes(key.toLowerCase())) {
        forwardHeaders.set(key, value);
      }
    }
    
    console.log(`🔄 Forward Headers:`, Object.fromEntries(forwardHeaders.entries()));
    
    const response = await fetch(apiUrl, {
      method: req.method,
      headers: forwardHeaders,
      body: req.method === 'GET' || req.method === 'HEAD' ? undefined : req.body,
    });
    
    console.log(`✅ API Response: ${response.status} ${response.statusText}`);
    console.log(`✅ Response Headers:`, Object.fromEntries(response.headers.entries()));
    
    // Check if response is actually from the API server
    if (response.headers.get('content-type')?.includes('text/html')) {
      console.log(`⚠️  WARNING: Got HTML response instead of JSON - possible routing issue!`);
      const body = await response.text();
      console.log(`⚠️  Response body preview:`, body.substring(0, 200));
      return new Response(JSON.stringify({ 
        error: 'Unexpected HTML response from API server',
        details: 'This suggests a routing issue'
      }), {
        status: 502,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        }
      });
    }
    
    // Forward the response back to client
    // Remove compression headers to prevent browser decoding issues
    const responseHeaders = new Headers(response.headers);
    responseHeaders.delete('content-encoding');
    responseHeaders.delete('content-length'); // Length may be wrong after removing compression
    
    console.log(`📤 Final Response Headers:`, Object.fromEntries(responseHeaders.entries()));
    
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: responseHeaders,
    });
    
  } catch (error) {
    console.error('❌ API proxy error:', error);
    console.error('❌ Error details:', error.message, error.stack);
    return new Response(JSON.stringify({ 
      error: 'API server unavailable',
      details: 'Failed to connect to chat API server',
      errorMessage: error.message
    }), {
      status: 503,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      }
    });
  }
}

const server = serve({
  port: process.env.PORT || 8080,
  hostname: "0.0.0.0",
  async fetch(req) {
    const url = new URL(req.url);
    const pathname = url.pathname;
    
    console.log(`🌐 INCOMING REQUEST: ${req.method} ${pathname}${url.search}`);
    console.log(`🌐 Full URL: ${req.url}`);
    console.log(`🌐 User-Agent: ${req.headers.get('user-agent') || 'none'}`);
    
    // Handle CORS preflight requests
    if (req.method === 'OPTIONS') {
      return new Response(null, {
        status: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, x-session-id, x-username',
          'Access-Control-Max-Age': '86400',
        },
      });
    }
    
    // Proxy API calls to chat server
    if (pathname.startsWith('/api/')) {
      console.log(`🔀 ROUTE: API proxy matched for ${pathname}`);
      return proxyToAPI(req, pathname);
    }
    
    // Health check endpoint
    if (pathname === '/health') {
      return new Response(JSON.stringify({ 
        status: 'healthy',
        proxy: 'running',
        timestamp: Date.now()
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Debug endpoint to check API_URL
    if (pathname === '/debug') {
      return new Response(JSON.stringify({ 
        API_SERVER_URL: API_SERVER_URL,
        env_API_URL: process.env.API_URL,
        NODE_ENV: process.env.NODE_ENV,
        PORT: process.env.PORT
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Serve static files (Flutter web app)
    console.log(`🔀 ROUTE: Static file serving for ${pathname}`);
    return serveStaticFile(pathname);
  },
});

console.log(`🚀 Reverse Proxy Server running on http://localhost:${server.port}`);
console.log(`📡 API calls /api/* → ${API_SERVER_URL}`);
console.log(`📁 Static files /* → ${STATIC_FILES_PATH}/`);
console.log(`🔍 Health check available at /health`);
console.log(`\n💡 Usage:`);
console.log(`   Frontend: http://localhost:${server.port}`);
console.log(`   API: http://localhost:${server.port}/api/...`); 