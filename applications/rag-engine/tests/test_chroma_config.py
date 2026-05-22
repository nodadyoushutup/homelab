import os
import unittest

from chroma_config import (
    DEFAULT_CHROMA_HTTP_PORT,
    DEFAULT_RAG_CHROMA_HOSTNAME,
    chroma_hostname_display,
    parse_chroma_hostname,
)


class ChromaHostnameTests(unittest.TestCase):
    def setUp(self) -> None:
        self._saved = os.environ.pop("RAG_CHROMA_HOSTNAME", None)

    def tearDown(self) -> None:
        if self._saved is None:
            os.environ.pop("RAG_CHROMA_HOSTNAME", None)
        else:
            os.environ["RAG_CHROMA_HOSTNAME"] = self._saved

    def test_default_when_unset(self) -> None:
        host, port = parse_chroma_hostname()
        self.assertEqual(host, "chromadb")
        self.assertEqual(port, 8000)
        self.assertEqual(DEFAULT_RAG_CHROMA_HOSTNAME, "chromadb:8000")

    def test_host_and_port(self) -> None:
        self.assertEqual(parse_chroma_hostname("127.0.0.1:12334"), ("127.0.0.1", 12334))
        self.assertEqual(parse_chroma_hostname("192.168.1.120:8000"), ("192.168.1.120", 8000))

    def test_hostname_without_port_uses_default(self) -> None:
        self.assertEqual(
            parse_chroma_hostname("test.example.com"),
            ("test.example.com", DEFAULT_CHROMA_HTTP_PORT),
        )
        self.assertEqual(parse_chroma_hostname("chromadb"), ("chromadb", DEFAULT_CHROMA_HTTP_PORT))

    def test_ipv6_bracket_form(self) -> None:
        self.assertEqual(parse_chroma_hostname("[::1]:9000"), ("::1", 9000))
        self.assertEqual(parse_chroma_hostname("[::1]"), ("::1", DEFAULT_CHROMA_HTTP_PORT))

    def test_display(self) -> None:
        self.assertEqual(chroma_hostname_display("test.example.com"), "test.example.com:8000")


if __name__ == "__main__":
    unittest.main()
