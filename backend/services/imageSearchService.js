const OpenAI = require('openai');

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

async function generateSearchQueryFromImage(base64Image, mimeType = 'image/jpeg') {
  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: `
Bu görseldeki ürünü kısa ve alışveriş aramasına uygun şekilde tanımla.

Kurallar:
- Sadece düz kısa arama sorgusu yaz.
- Marka net görünmüyorsa uydurma.
- Renk, ürün tipi ve ayırt edici özelliği ekleyebilirsin.
- Cümle kurma, açıklama yapma.
- Sadece ürün arama sorgusu döndür.

Örnek çıktı:
siyah spor ayakkabı
beyaz kablosuz kulaklık
gri ofis sandalyesi
            `.trim(),
          },
          {
            type: 'image_url',
            image_url: {
              url: `data:${mimeType};base64,${base64Image}`,
            },
          },
        ],
      },
    ],
    temperature: 0.2,
  });

  return response.choices?.[0]?.message?.content?.trim() || '';
}

module.exports = {
  generateSearchQueryFromImage,
};