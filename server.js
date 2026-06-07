const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 5000;

const mimeTypes = {
  '.html': 'text/html',
  '.css':  'text/css',
  '.js':   'application/javascript',
  '.json': 'application/json',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif':  'image/gif',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
  '.woff': 'font/woff',
  '.woff2':'font/woff2',
};

const server = http.createServer((req, res) => {
  let urlPath = req.url.split('?')[0];

  if (urlPath === '/' || urlPath === '') {
    urlPath = '/index.html';
  }

  let filePath;
  if (urlPath.startsWith('/assets/')) {
    filePath = path.join(__dirname, urlPath);
  } else {
    filePath = path.join(__dirname, 'web', urlPath);
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      if (urlPath !== '/index.html') {
        fs.readFile(path.join(__dirname, 'web', 'index.html'), (err2, data2) => {
          if (err2) {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('Not found');
          } else {
            res.writeHead(200, { 'Content-Type': 'text/html' });
            res.end(data2);
          }
        });
      } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not found');
      }
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = mimeTypes[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Aika Assistant landing page running at http://0.0.0.0:${PORT}`);
});
