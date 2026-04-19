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

async function generateSearchQueryFromImages(images = [], userMessage = '') {
    const content = [
      {
        type: 'text',
        text: `
  Kullanıcı bir veya daha fazla ürün görseli yükledi ve şu isteği yazdı:
  "${userMessage}"
  
  Görevin:
  - Görsellerdeki ana ürünü veya ortak ürünü anlamak
  - Alışveriş aramasına uygun kısa bir sorgu üretmek
  
  Kurallar:
  - Sadece düz kısa arama sorgusu döndür
  - Açıklama yazma
  - Marka net değilse uydurma
  - Ürün tipi + renk + ayırt edici özellik yazabilirsin
  
  Örnek:
  siyah deri ceket
  beyaz spor ayakkabı
  gri modern koltuk
        `.trim(),
      },
    ];
  
    for (const image of images.slice(0, 3)) {
      content.push({
        type: 'image_url',
        image_url: {
          url: `data:${image.mimeType};base64,${image.base64}`,
        },
      });
    }
  
    const response = await client.chat.completions.create({
      model: 'gpt-4.1-mini',
      messages: [
        {
          role: 'user',
          content,
        },
      ],
      temperature: 0.2,
    });
  
    return response.choices?.[0]?.message?.content?.trim() || '';
  }

module.exports = {
  generateSearchQueryFromImage,
  generateSearchQueryFromImages,
};