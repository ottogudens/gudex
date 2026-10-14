"""Bounded PDF worker. Parent enforces a wall-clock timeout."""
import json
import sys


def main():
    # PDFs are user uploads: keep parser resource consumption outside the API worker.
    # ``resource`` is available on Unix (including Railway) but not on
    # Windows. The subprocess isolation and parent timeout still protect local
    # Windows development, while production retains the stricter OS limits.
    try:
        import resource
    except ImportError:
        resource = None
    if resource is not None:
        resource.setrlimit(resource.RLIMIT_AS, (512 * 1024 * 1024, 512 * 1024 * 1024))
        resource.setrlimit(resource.RLIMIT_CPU, (2, 2))
    from pypdf import PdfReader
    try:
        reader = PdfReader(sys.argv[1])
        text = ""
        truncated = len(reader.pages) > 20
        for page in reader.pages[:20]:
            text += (page.extract_text() or "") + "\n"
            if len(text) > 4000:
                truncated = True
                break
        text = text.strip()[:4000]
        print(json.dumps({"status": "truncated" if text and truncated else "read" if text else "no_text",
                          "text": text}))
    except Exception:
        print(json.dumps({"status": "unreadable", "text": ""}))


if __name__ == "__main__":
    main()
