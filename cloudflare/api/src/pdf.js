const enc = new TextEncoder();

function clean(value) {
  return String(value ?? "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^\x20-\x7E]/g, "?").replace(/([\\()])/g, "\\$1");
}

function wrapped(value, width = 88) {
  const words = clean(value).split(/\s+/), lines = []; let line = "";
  for (const word of words) {
    if (!word) continue;
    if (word.length > width) {
      if (line) lines.push(line);
      for (let i = 0; i < word.length; i += width) lines.push(word.slice(i, i + width));
      line = "";
    } else if (!line) line = word;
    else if (`${line} ${word}`.length <= width) line += ` ${word}`;
    else { lines.push(line); line = word; }
  }
  if (line) lines.push(line);
  return lines.length ? lines : [""];
}

function makeStream(lines, pageIndex, pageCount, thermal = false, pageHeight = 842) {
  const perPage = thermal ? lines.length : 48;
  const visible = lines.slice(pageIndex * perPage, (pageIndex + 1) * perPage);
  const commands = thermal ? ["BT", "/F1 8 Tf", `12 ${pageHeight - 18} Td`, "10 TL"] : ["BT", "/F1 10 Tf", "50 790 Td", "14 TL"];
  for (const line of visible) commands.push(`(${clean(line)}) Tj`, "T*");
  commands.push(`(Pagina ${pageIndex + 1} de ${pageCount}) Tj`, "ET");
  return commands.join("\n");
}

export function createTextPdf(title, details, { thermal = false } = {}) {
  const lines = [];
  const width = thermal ? 38 : 88;
  for (const value of ["Gudex Lubricentro y Serviteca", title, "", ...details]) lines.push(...wrapped(value, width));
  const pageCount = thermal ? 1 : Math.max(1, Math.ceil(lines.length / 48)), objects = [];
  const pageHeight = thermal ? Math.max(140, Math.ceil(lines.length * 10 + 28)) : 842;
  objects.push("<< /Type /Catalog /Pages 2 0 R >>");
  const kids = Array.from({ length: pageCount }, (_, i) => `${3 + i * 2} 0 R`).join(" ");
  objects.push(`<< /Type /Pages /Kids [${kids}] /Count ${pageCount} >>`);
  for (let i = 0; i < pageCount; i++) {
    const pageId = 3 + i * 2, streamId = pageId + 1, stream = makeStream(lines, i, pageCount, thermal, pageHeight);
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${thermal ? 226.77 : 595} ${pageHeight}] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> /Contents ${streamId} 0 R >>`);
    objects.push(`<< /Length ${enc.encode(stream).length} >>\nstream\n${stream}\nendstream`);
  }
  let output = "%PDF-1.4\n", offsets = [0];
  objects.forEach((object, i) => { offsets.push(enc.encode(output).length); output += `${i + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = enc.encode(output).length;
  output += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) output += `${String(offset).padStart(10, "0")} 00000 n \n`;
  output += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return enc.encode(output);
}

export function pdfResponse(bytes, filename, inline = false) {
  return new Response(bytes, { headers: { "Content-Type": "application/pdf", "Content-Disposition": `${inline ? "inline" : "attachment"}; filename="${filename}"`, "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" } });
}
