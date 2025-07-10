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
    
    // Forward the request to the API server
    const response = await fetch(apiUrl, {
      method: req.method,
      headers: req.headers,
      body: req.method === 'GET' || req.method === 'HEAD' ? undefined : req.body,
    });
    
    // Forward the response back to client
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
    });
    
  } catch (error) {
    console.error('❌ API proxy error:', error);
    return new Response(JSON.stringify({ 
      error: 'API server unavailable',
      details: 'Failed to connect to chat API server'
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
    
    // Serve static files (Flutter web app)
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