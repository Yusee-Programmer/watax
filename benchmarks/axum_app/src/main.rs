// Rust HTTP benchmark server for comparison against watax/FastAPI.
// axum itself isn't available in the offline cargo cache here, so this uses
// hyper 1.x server APIs directly (axum is a thin routing layer over hyper -
// raw hyper is the closest available comparison and a fair upper bound).
// Mirrors bench/watax_app/src/main.tr and bench/fastapi_app/main.py:
// GET / (plain text), GET /json (JSON).

use bytes::Bytes;
use http_body::Frame;
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response};
use hyper_util::rt::TokioIo;
use std::convert::Infallible;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::net::TcpListener;

struct FullBody(Option<Bytes>);

impl FullBody {
    fn new(data: Bytes) -> Self {
        FullBody(Some(data))
    }
}

impl http_body::Body for FullBody {
    type Data = Bytes;
    type Error = Infallible;

    fn poll_frame(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        Poll::Ready(self.0.take().map(|d| Ok(Frame::data(d))))
    }
}

// ── In-memory "World"/"Fortune" data (TechEmpower-style; no real DB) ──────────
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::sync::OnceLock;

fn worlds() -> &'static Vec<AtomicI32> {
    static WORLDS: OnceLock<Vec<AtomicI32>> = OnceLock::new();
    WORLDS.get_or_init(|| {
        let mut st: u64 = 20260620;
        (0..10000)
            .map(|_| {
                st = st.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                AtomicI32::new((((st >> 33) as i64).rem_euclid(10000) + 1) as i32)
            })
            .collect()
    })
}

fn rand_id() -> i32 {
    static STATE: AtomicU64 = AtomicU64::new(0x9e3779b97f4a7c15);
    let mut x = STATE.load(Ordering::Relaxed);
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    STATE.store(x, Ordering::Relaxed);
    ((x >> 33) % 10000 + 1) as i32
}

fn query_count(q: &str) -> usize {
    for kv in q.split('&') {
        if let Some(v) = kv.strip_prefix("queries=") {
            return v.parse::<usize>().unwrap_or(1).clamp(1, 500);
        }
    }
    1
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
        .replace('"', "&quot;").replace('\'', "&#x27;")
}

fn json_resp(body: String) -> Response<FullBody> {
    Response::builder()
        .header("Content-Type", "application/json")
        .body(FullBody::new(Bytes::from(body)))
        .unwrap()
}

async fn handle(req: Request<Incoming>) -> Result<Response<FullBody>, Infallible> {
    let path = req.uri().path().to_string();
    let query = req.uri().query().unwrap_or("").to_string();
    let resp = if path == "/db" {
        let id = rand_id();
        let rn = worlds()[(id - 1) as usize].load(Ordering::Relaxed);
        json_resp(serde_json::json!({"id": id, "randomNumber": rn}).to_string())
    } else if path == "/queries" {
        let n = query_count(&query);
        let rows: Vec<_> = (0..n).map(|_| {
            let id = rand_id();
            serde_json::json!({"id": id, "randomNumber": worlds()[(id-1) as usize].load(Ordering::Relaxed)})
        }).collect();
        json_resp(serde_json::Value::Array(rows).to_string())
    } else if path == "/updates" {
        let n = query_count(&query);
        let rows: Vec<_> = (0..n).map(|_| {
            let id = rand_id();
            let nv = rand_id();
            worlds()[(id-1) as usize].store(nv, Ordering::Relaxed);
            serde_json::json!({"id": id, "randomNumber": nv})
        }).collect();
        json_resp(serde_json::Value::Array(rows).to_string())
    } else if path == "/fortunes" {
        let mut fs: Vec<(i32, String)> = vec![
            (1, "fortune: No such file or directory".into()),
            (2, "A computer scientist is someone who fixes things that aren't broken.".into()),
            (3, "After enough decimal places, nobody gives a damn.".into()),
            (11, "<script>alert(\"This should not be displayed in a browser alert box.\");</script>".into()),
            (12, "フレームワークのベンチマーク".into()),
            (0, "Additional fortune added at request time.".into()),
        ];
        fs.sort_by(|a, b| a.1.cmp(&b.1));
        let mut html = String::from("<!DOCTYPE html><html><head><title>Fortunes</title></head><body><table><tr><th>id</th><th>message</th></tr>");
        for (id, m) in &fs {
            html.push_str(&format!("<tr><td>{}</td><td>{}</td></tr>", id, html_escape(m)));
        }
        html.push_str("</table></body></html>");
        Response::builder().header("Content-Type", "text/html; charset=utf-8")
            .body(FullBody::new(Bytes::from(html))).unwrap()
    } else if path == "/plaintext-big" {
        let s = "The quick brown fox jumps over the lazy dog. ".repeat(256);
        Response::builder().header("Content-Type", "text/plain; charset=utf-8")
            .body(FullBody::new(Bytes::from(s))).unwrap()
    } else if path == "/json" {
        let body = serde_json::json!({"message": "Hello, World!", "id": 1, "ok": true});
        Response::builder()
            .header("Content-Type", "application/json")
            .body(FullBody::new(Bytes::from(body.to_string())))
            .unwrap()
    } else if path == "/users" {
        // Larger JSON payload: a 20-element array of small objects.
        let users: Vec<serde_json::Value> = (0..20)
            .map(|i| serde_json::json!({ "id": i, "name": "user", "active": true }))
            .collect();
        let body = serde_json::Value::Array(users);
        Response::builder()
            .header("Content-Type", "application/json")
            .body(FullBody::new(Bytes::from(body.to_string())))
            .unwrap()
    } else if let Some(name) = path.strip_prefix("/greet/") {
        // Path-parameter route: GET /greet/:name -> {"hello": <name>}
        let body = serde_json::json!({ "hello": name });
        Response::builder()
            .header("Content-Type", "application/json")
            .body(FullBody::new(Bytes::from(body.to_string())))
            .unwrap()
    } else {
        Response::builder()
            .header("Content-Type", "text/plain; charset=utf-8")
            .body(FullBody::new(Bytes::from_static(b"Hello, World!")))
            .unwrap()
    };
    Ok(resp)
}

fn main() {
    let workers: usize = std::env::var("AXUM_WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(4);
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(workers)
        .enable_all()
        .build()
        .unwrap()
        .block_on(serve());
}

async fn serve() {
    let listener = TcpListener::bind("127.0.0.1:8300").await.unwrap();
    loop {
        let (stream, _) = listener.accept().await.unwrap();
        let io = TokioIo::new(stream);
        tokio::task::spawn(async move {
            let _ = http1::Builder::new()
                .keep_alive(true)
                .serve_connection(io, service_fn(handle))
                .await;
        });
    }
}
