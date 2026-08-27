const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const REVIEWS_FILE = path.join(__dirname, 'reviews.json');

const MIME_TYPES = {
    '.html': 'text/html; charset=UTF-8',
    '.css': 'text/css; charset=UTF-8',
    '.js': 'text/javascript; charset=UTF-8',
    '.json': 'application/json; charset=UTF-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml'
};

function readReviews() {
    try {
        if (!fs.existsSync(REVIEWS_FILE)) {
            fs.writeFileSync(REVIEWS_FILE, '[]', 'utf8');
            return [];
        }
        const data = fs.readFileSync(REVIEWS_FILE, 'utf8');
        return JSON.parse(data || '[]');
    } catch (err) {
        console.error('Error reading reviews file:', err);
        return [];
    }
}

function saveReviews(reviews) {
    fs.writeFileSync(REVIEWS_FILE, JSON.stringify(reviews, null, 2), 'utf8');
}

const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const pathname = url.pathname;

    // API Routes
    if (pathname === '/api/reviews') {
        if (req.method === 'GET') {
            const reviews = readReviews();
            res.writeHead(200, {
                'Content-Type': 'application/json; charset=UTF-8',
                'Access-Control-Allow-Origin': '*'
            });
            res.end(JSON.stringify(reviews));
            return;
        }

        if (req.method === 'POST') {
            let body = '';
            req.on('data', chunk => {
                body += chunk.toString();
                // Avoid massive payload attack
                if (body.length > 1e6) {
                    req.destroy();
                }
            });

            req.on('end', () => {
                try {
                    const data = JSON.parse(body);
                    if (!data.name || !data.message) {
                        res.writeHead(400, { 'Content-Type': 'application/json; charset=UTF-8' });
                        res.end(JSON.stringify({ error: "Ім'я та текст відгуку є обов'язковими" }));
                        return;
                    }

                    const rating = Math.min(5, Math.max(1, parseInt(data.rating, 10) || 5));
                    const categoryLabels = {
                        'review': "Відгук про використання",
                        'question': "Запитання консультанту",
                        'suggestion': "Пропозиція / Порада"
                    };

                    const newReview = {
                        id: 'rev-' + Date.now(),
                        name: String(data.name).trim().slice(0, 100),
                        email: data.email ? String(data.email).trim().slice(0, 100) : '',
                        rating: rating,
                        category: data.category || 'review',
                        categoryLabel: categoryLabels[data.category] || "Відгук про використання",
                        message: String(data.message).trim().slice(0, 2000),
                        date: new Date().toISOString().split('T')[0]
                    };

                    const reviews = readReviews();
                    reviews.unshift(newReview);
                    saveReviews(reviews);

                    res.writeHead(201, {
                        'Content-Type': 'application/json; charset=UTF-8',
                        'Access-Control-Allow-Origin': '*'
                    });
                    res.end(JSON.stringify({ success: true, review: newReview }));
                } catch (err) {
                    console.error('Error processing review:', err);
                    res.writeHead(400, { 'Content-Type': 'application/json; charset=UTF-8' });
                    res.end(JSON.stringify({ error: 'Некоректний формат даних' }));
                }
            });
            return;
        }

        if (req.method === 'OPTIONS') {
            res.writeHead(204, {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            });
            res.end();
            return;
        }
    }

    // Static File Serving
    let safePath = pathname === '/' ? '/index.html' : pathname;
    let filePath = path.join(__dirname, path.normalize(safePath).replace(/^(\.\.[\/\\])+/, ''));
    const extname = String(path.extname(filePath)).toLowerCase();
    const contentType = MIME_TYPES[extname] || 'application/octet-stream';

    fs.readFile(filePath, (error, content) => {
        if (error) {
            if (error.code === 'ENOENT') {
                res.writeHead(404, { 'Content-Type': 'text/plain; charset=UTF-8' });
                res.end('404 Not Found');
            } else {
                res.writeHead(500, { 'Content-Type': 'text/plain; charset=UTF-8' });
                res.end(`Server Error: ${error.code}`);
            }
        } else {
            res.writeHead(200, { 'Content-Type': contentType });
            res.end(content);
        }
    });
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`Server is running at http://localhost:${PORT}/`);
});
