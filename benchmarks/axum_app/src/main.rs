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

async fn handle(req: Request<Incoming>) -> Result<Response<FullBody>, Infallible> {
    let path = req.uri().path().to_string();
    let resp = if path == "/json" {
        let body = serde_json::json!({"message": "Hello, World!", "id": 1, "ok": true});
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

#[tokio::main]
async fn main() {
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
